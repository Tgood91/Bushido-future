// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {MockMailbox} from "@hyperlane-xyz/core/contracts/mock/MockMailbox.sol";
import {TestPostDispatchHook} from "@hyperlane-xyz/core/contracts/test/TestPostDispatchHook.sol";
import {HypERC20} from "@hyperlane-xyz/core/contracts/token/HypERC20.sol";
import {HypERC20Collateral} from "@hyperlane-xyz/core/contracts/token/HypERC20Collateral.sol";
import {BushidoFeeVault, IERC20} from "../src/BushidoFeeVault.sol";
import {WarpInventoryBridge, IWarpRoute} from "../src/bridge/WarpInventoryBridge.sol";
import {MockUSDC} from "./mocks/MockUSDC.sol";
import {vm} from "./mocks/Vm.sol";

/// @notice Inventory rebalancing over a REAL Hyperlane warp route (open-source contracts) between two
///         simulated EVM testnets: Base Sepolia holds tUSDC as collateral, Arbitrum Sepolia has the synthetic.
///         MockMailbox queues messages until processNextInboundMessage(), so in-flight state is observable.
contract WarpInventoryBridgeTest {
    uint32 constant BASE_SEPOLIA = 84532;
    uint32 constant ARB_SEPOLIA = 421614;
    uint256 constant U = 1e6;
    address constant OWNER = address(0xB051D0);
    address constant KEEPER = address(0xEE9E5);
    address constant STRANGER = address(0xBAD);

    MockMailbox mbBase;
    MockMailbox mbArb;
    MockUSDC usdc; // home token on Base Sepolia
    HypERC20Collateral collateral; // warp route on Base Sepolia
    HypERC20 synthetic; // warp route + token on Arbitrum Sepolia

    BushidoFeeVault vaultBase;
    BushidoFeeVault vaultArb;
    WarpInventoryBridge bridgeBase;
    WarpInventoryBridge bridgeArb;

    function setUp() public {
        mbBase = new MockMailbox(BASE_SEPOLIA);
        mbArb = new MockMailbox(ARB_SEPOLIA);
        mbBase.addRemoteMailbox(ARB_SEPOLIA, mbArb);
        mbArb.addRemoteMailbox(BASE_SEPOLIA, mbBase);

        usdc = new MockUSDC();
        collateral = new HypERC20Collateral(address(usdc), 1, 1, address(mbBase));
        collateral.initialize(address(0), address(0), address(this));
        synthetic = new HypERC20(6, 1, 1, address(mbArb));
        synthetic.initialize(0, "Bushido Test USDC", "tUSDC", address(0), address(0), address(this));
        collateral.enrollRemoteRouter(ARB_SEPOLIA, bytes32(uint256(uint160(address(synthetic)))));
        synthetic.enrollRemoteRouter(BASE_SEPOLIA, bytes32(uint256(uint160(address(collateral)))));

        vaultBase = new BushidoFeeVault(IERC20(address(usdc)), OWNER, 6_250 * U, 25_000 * U, 500 * U);
        vaultArb = new BushidoFeeVault(IERC20(address(synthetic)), OWNER, 6_250 * U, 25_000 * U, 500 * U);
        bridgeBase = new WarpInventoryBridge(vaultBase, IWarpRoute(address(collateral)), OWNER, 20_000 * U);
        bridgeArb = new WarpInventoryBridge(vaultArb, IWarpRoute(address(synthetic)), OWNER, 20_000 * U);

        vm.startPrank(OWNER);
        vaultBase.setRebalancer(address(bridgeBase));
        vaultArb.setRebalancer(address(bridgeArb));
        vaultBase.setSolver(OWNER);
        bridgeBase.setRemoteVault(ARB_SEPOLIA, address(vaultArb));
        bridgeArb.setRemoteVault(BASE_SEPOLIA, address(vaultBase));
        bridgeBase.setKeeper(KEEPER);
        vm.stopPrank();
        vm.deal(address(bridgeBase), 1 ether);
        vm.deal(address(bridgeArb), 1 ether);

        usdc.mint(address(this), 10_000 * U);
        usdc.approve(address(vaultBase), 10_000 * U);
        vaultBase.seedInventory(10_000 * U);
    }

    function _eq(uint256 a, uint256 b, string memory m) internal pure {
        require(a == b, m);
    }

    // ---------------------------------------------------------------- happy path
    function test_shipDeliverAbsorb() public {
        vm.prank(OWNER);
        bridgeBase.rebalance(ARB_SEPOLIA, 4_000 * U);

        // in flight: left Base, not yet on Arbitrum
        _eq(vaultBase.inventory(), 6_000 * U, "base down");
        _eq(usdc.balanceOf(address(collateral)), 4_000 * U, "locked as collateral");
        _eq(vaultArb.absorbSurplus(), 0, "nothing arrived yet");

        mbArb.processNextInboundMessage(); // relayer delivers
        _eq(synthetic.balanceOf(address(vaultArb)), 4_000 * U, "synthetic minted to the vault");
        _eq(vaultArb.inventory(), 0, "not yet credited");
        vm.prank(STRANGER);
        _eq(vaultArb.absorbSurplus(), 4_000 * U, "anyone can credit");
        _eq(vaultArb.inventory(), 4_000 * U, "arb inventory");
        _eq(bridgeBase.shippedTo(ARB_SEPOLIA), 4_000 * U, "tracked");
        _eq(synthetic.balanceOf(address(vaultArb)), vaultArb.accounted(), "arb invariant");
        _eq(usdc.balanceOf(address(vaultBase)), vaultBase.accounted(), "base invariant");
    }

    function test_roundTripReleasesCollateral() public {
        vm.prank(KEEPER);
        bridgeBase.rebalance(ARB_SEPOLIA, 3_000 * U);
        mbArb.processNextInboundMessage();
        vaultArb.absorbSurplus();

        vm.prank(OWNER);
        bridgeArb.rebalance(BASE_SEPOLIA, 1_000 * U); // synthetic burned on Arbitrum
        _eq(synthetic.totalSupply(), 2_000 * U, "burned");
        mbBase.processNextInboundMessage(); // collateral released on Base
        vaultBase.absorbSurplus();

        _eq(vaultBase.inventory(), 8_000 * U, "base after round trip");
        _eq(vaultArb.inventory(), 2_000 * U, "arb after round trip");
        _eq(usdc.balanceOf(address(collateral)), synthetic.totalSupply(), "collateral backs synthetic 1:1");
    }

    function test_arrivalGraduatesDestination() public {
        vm.prank(OWNER);
        bridgeBase.rebalance(ARB_SEPOLIA, 6_250 * U);
        mbArb.processNextInboundMessage();
        vaultArb.absorbSurplus();
        vaultArb.advancePhase();
        _eq(uint8(vaultArb.phase()), 1, "SELF_SOLVE on bridged inventory");
    }

    function test_absorbIsIdempotentAndIgnoresAccountedFunds() public {
        _eq(vaultBase.absorbSurplus(), 0, "no surplus when fully accounted");
        usdc.mint(address(vaultBase), 5 * U); // a stray transfer
        _eq(vaultBase.absorbSurplus(), 5 * U, "stray tokens become inventory");
        _eq(vaultBase.absorbSurplus(), 0, "second call credits nothing");
        _eq(vaultBase.inventory(), 10_005 * U, "inventory");
    }

    // ---------------------------------------------------------------- guardrails
    function test_onlyOwnerOrKeeper() public {
        vm.prank(STRANGER);
        vm.expectRevert(WarpInventoryBridge.NotOwnerOrKeeper.selector);
        bridgeBase.rebalance(ARB_SEPOLIA, 1 * U);
    }

    function test_onlyRebalancerPullsFromVault() public {
        vm.prank(STRANGER);
        vm.expectRevert(BushidoFeeVault.NotRebalancer.selector);
        vaultBase.sendInventory(1 * U);
    }

    function test_unknownDomain() public {
        vm.prank(OWNER);
        vm.expectRevert(abi.encodeWithSelector(WarpInventoryBridge.UnknownDomain.selector, uint32(97)));
        bridgeBase.rebalance(97, 1 * U);
    }

    function test_maxPerTransfer() public {
        vm.prank(OWNER);
        vm.expectRevert(abi.encodeWithSelector(WarpInventoryBridge.OverMaxPerTransfer.selector, 20_001 * U, 20_000 * U));
        bridgeBase.rebalance(ARB_SEPOLIA, 20_001 * U);
    }

    function test_cannotShipMoreThanIdle() public {
        vm.prank(OWNER);
        vm.expectRevert(BushidoFeeVault.InsufficientInventory.selector);
        bridgeBase.rebalance(ARB_SEPOLIA, 10_001 * U);
    }

    function test_utilisationCapBlocksShipping() public {
        vaultBase.advancePhase();
        vm.prank(OWNER);
        vaultBase.drawForFill("f", 500 * U, false); // outstanding 500 of capital 10,000
        // shipping 9,400 leaves capital 600 with 500 outstanding = 83% > 80%
        vm.prank(OWNER);
        vm.expectRevert(BushidoFeeVault.UtilizationExceeded.selector);
        bridgeBase.rebalance(ARB_SEPOLIA, 9_400 * U);
    }

    function test_shippingAwayDemotes() public {
        vaultBase.advancePhase(); // SELF_SOLVE at 10,000
        vm.prank(OWNER);
        bridgeBase.rebalance(ARB_SEPOLIA, 4_000 * U); // 6,000 < 6,250
        _eq(uint8(vaultBase.phase()), 0, "back to ROUTING");
    }

    function test_rejectsMismatchedRoute() public {
        vm.expectRevert(WarpInventoryBridge.TokenMismatch.selector);
        new WarpInventoryBridge(vaultArb, IWarpRoute(address(collateral)), OWNER, 1);
    }

    function test_paysRelayFeeInNativeGas() public {
        TestPostDispatchHook(address(mbBase.defaultHook())).setFee(0.01 ether);
        (uint256 gas,) = bridgeBase.quote(ARB_SEPOLIA, 1 * U);
        require(gas >= 0.01 ether, "relay fee quoted");

        vm.deal(address(bridgeBase), 0);
        vm.prank(OWNER);
        vm.expectRevert(abi.encodeWithSelector(WarpInventoryBridge.InsufficientGas.selector, 0, gas));
        bridgeBase.rebalance(ARB_SEPOLIA, 1 * U);

        vm.deal(address(bridgeBase), gas);
        vm.prank(OWNER);
        bridgeBase.rebalance(ARB_SEPOLIA, 1 * U);
        _eq(address(bridgeBase).balance, 0, "gas spent on the relay fee");
    }
}
