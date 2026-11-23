// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {MockMailbox} from "@hyperlane-xyz/core/contracts/mock/MockMailbox.sol";
import {HypERC20} from "@hyperlane-xyz/core/contracts/token/HypERC20.sol";
import {HypERC20Collateral} from "@hyperlane-xyz/core/contracts/token/HypERC20Collateral.sol";
import {BushidoFeeVault, IERC20} from "../src/BushidoFeeVault.sol";
import {WarpInventoryBridge, IWarpRoute} from "../src/bridge/WarpInventoryBridge.sol";
import {IntentSettler, IHyperlaneMailbox} from "../src/intents/IntentSettler.sol";
import {MockUSDC} from "./mocks/MockUSDC.sol";
import {vm} from "./mocks/Vm.sol";

/// @notice Testnet solving between Base Sepolia (tUSDC collateral) and Arbitrum Sepolia (synthetic tUSDC),
///         on Hyperlane's real warp contracts and MockMailbox (messages queue until processed).
contract IntentSettlerTest {
    uint32 constant BASE = 84532;
    uint32 constant ARB = 421614;
    uint256 constant U = 1e6;
    address constant OWNER = address(0xB051D0);
    address constant SOLVER = address(0x50173);
    address constant USER = address(0x05E2);
    address constant RECIPIENT = address(0xEC1);
    address constant STRANGER = address(0xBAD);

    MockMailbox mbBase;
    MockMailbox mbArb;
    MockUSDC usdc;
    HypERC20Collateral collateral;
    HypERC20 synthetic;
    BushidoFeeVault vaultBase;
    BushidoFeeVault vaultArb;
    WarpInventoryBridge bridgeBase;
    IntentSettler settlerBase;
    IntentSettler settlerArb;

    function setUp() public {
        vm.warp(1_800_000_000);
        mbBase = new MockMailbox(BASE);
        mbArb = new MockMailbox(ARB);
        mbBase.addRemoteMailbox(ARB, mbArb);
        mbArb.addRemoteMailbox(BASE, mbBase);

        usdc = new MockUSDC();
        collateral = new HypERC20Collateral(address(usdc), 1, 1, address(mbBase));
        collateral.initialize(address(0), address(0), address(this));
        synthetic = new HypERC20(6, 1, 1, address(mbArb));
        synthetic.initialize(0, "Bushido Test USDC", "tUSDC", address(0), address(0), address(this));
        collateral.enrollRemoteRouter(ARB, bytes32(uint256(uint160(address(synthetic)))));
        synthetic.enrollRemoteRouter(BASE, bytes32(uint256(uint160(address(collateral)))));

        // testnet thresholds: SELF_SOLVE 1,000 / BRIDGE 2,000 / max fill 500
        vaultBase = new BushidoFeeVault(IERC20(address(usdc)), OWNER, 1_000 * U, 2_000 * U, 500 * U);
        vaultArb = new BushidoFeeVault(IERC20(address(synthetic)), OWNER, 1_000 * U, 2_000 * U, 500 * U);
        bridgeBase = new WarpInventoryBridge(vaultBase, IWarpRoute(address(collateral)), OWNER, 100_000 * U);
        settlerBase = new IntentSettler(IHyperlaneMailbox(address(mbBase)), IWarpRoute(address(collateral)), OWNER);
        settlerArb = new IntentSettler(IHyperlaneMailbox(address(mbArb)), IWarpRoute(address(synthetic)), OWNER);

        vm.startPrank(OWNER);
        vaultBase.setRebalancer(address(bridgeBase));
        vaultArb.setSolver(SOLVER);
        vaultBase.setSolver(SOLVER);
        bridgeBase.setRemoteVault(ARB, address(vaultArb));
        settlerBase.setPeer(ARB, address(settlerArb), address(vaultArb));
        settlerArb.setPeer(BASE, address(settlerBase), address(vaultBase));
        vm.stopPrank();

        // Base vault funded; ship 5,000 to Arbitrum and graduate it to BRIDGE
        usdc.mint(address(this), 10_000 * U);
        usdc.approve(address(vaultBase), 10_000 * U);
        vaultBase.seedInventory(10_000 * U);
        vm.prank(OWNER);
        bridgeBase.rebalance(ARB, 5_000 * U);
        mbArb.processNextInboundMessage();
        vm.prank(OWNER);
        vaultArb.absorbSurplus();
        vaultArb.advancePhase();
        vaultArb.advancePhase();
        require(uint8(vaultArb.phase()) == 2, "arb vault in BRIDGE");

        usdc.mint(USER, 1_000 * U);
        vm.prank(USER);
        usdc.approve(address(settlerBase), type(uint256).max);
        vm.prank(SOLVER);
        synthetic.approve(address(settlerArb), type(uint256).max);
    }

    function _eq(uint256 a, uint256 b, string memory m) internal pure {
        require(a == b, m);
    }

    function _open(uint256 amountOut) internal returns (bytes32 h, IntentSettler.Params memory p) {
        vm.prank(USER);
        (h, p) = settlerBase.open(ARB, RECIPIENT, amountOut, uint64(block.timestamp + 10 minutes));
    }

    function _solve(bytes32 h, IntentSettler.Params memory p) internal {
        vm.startPrank(SOLVER);
        vaultArb.drawForFill(h, p.amountOut, true);
        settlerArb.fill(p);
        vm.stopPrank();
    }

    function _status(bytes32 h) internal view returns (uint8 s) {
        (IntentSettler.Status st,,,,,) = settlerBase.orders(h);
        s = uint8(st);
    }

    // ----------------------------------------------------------------- happy path
    function test_fullSolveBaseToArbitrum() public {
        uint256 invBefore = vaultArb.inventory();
        uint256 resBefore = vaultArb.reserve();
        uint256 opsBefore = vaultArb.ops();

        (bytes32 h, IntentSettler.Params memory p) = _open(100 * U);
        _eq(p.amountIn, 100_250_000, "user pays amountOut + 25 bps");
        _eq(usdc.balanceOf(address(settlerBase)), 100_250_000, "deposit escrowed on Base");

        _solve(h, p);
        _eq(synthetic.balanceOf(RECIPIENT), 100 * U, "recipient paid on Arbitrum");
        _eq(vaultArb.outstanding(), 100 * U, "vault fronted the fill");

        mbBase.processNextInboundMessage(); // Hyperlane delivers the fill confirmation
        _eq(_status(h), 2, "Filled on origin");

        vm.prank(STRANGER);
        settlerBase.repay(h); // permissionless
        _eq(_status(h), 3, "Repaid");
        mbArb.processNextInboundMessage(); // warp route delivers principal + fee to the Arbitrum vault

        vm.prank(SOLVER);
        vaultArb.settleFillFromBalance(h, 100_250_000);
        _eq(vaultArb.outstanding(), 0, "fill closed");
        // 0.25 USDC profit split 70/10/20
        _eq(vaultArb.inventory(), invBefore + 175_000, "70% of fee to inventory");
        _eq(vaultArb.reserve(), resBefore + 25_000, "10% to reserve");
        _eq(vaultArb.ops(), opsBefore + 50_000, "20% to ops");
        _eq(synthetic.balanceOf(address(vaultArb)), vaultArb.accounted(), "arb vault invariant");
        _eq(usdc.balanceOf(address(collateral)), synthetic.totalSupply(), "warp route fully backed");
    }

    function test_feeRoundsUp() public view {
        _eq(settlerBase.feeFor(1), 1, "1 unit still pays a fee");
        _eq(settlerBase.feeFor(100 * U), 250_000, "25 bps");
    }

    // ----------------------------------------------------------------- user safety
    function test_tamperedFillIsIgnoredAndUserRefunds() public {
        (bytes32 h, IntentSettler.Params memory p) = _open(100 * U);
        IntentSettler.Params memory bad = p;
        bad.recipient = STRANGER; // solver pays someone else
        vm.prank(SOLVER);
        vaultArb.drawForFill(h, p.amountOut, true);
        vm.prank(SOLVER);
        settlerArb.fill(bad);
        mbBase.processNextInboundMessage();
        _eq(_status(h), 1, "order still Open: hash didn't match");

        vm.prank(USER);
        vm.expectRevert(IntentSettler.NotRefundable.selector);
        settlerBase.refund(h); // not before deadline + grace

        vm.warp(block.timestamp + 10 minutes + 1 hours + 1);
        uint256 before = usdc.balanceOf(USER);
        settlerBase.refund(h);
        _eq(usdc.balanceOf(USER), before + 100_250_000, "full refund");
    }

    function test_lateFillAfterRefundIsIgnored() public {
        (bytes32 h, IntentSettler.Params memory p) = _open(100 * U);
        vm.warp(block.timestamp + 2 hours);
        settlerBase.refund(h);
        vm.warp(p.deadline); // dest clock still inside the deadline (clocks can differ)
        _solve(h, p);
        mbBase.processNextInboundMessage();
        _eq(_status(h), 4, "stays Refunded");
        vm.expectRevert(IntentSettler.NotFilled.selector);
        settlerBase.repay(h);
    }

    // ----------------------------------------------------------------- solver safety
    function test_doubleFillRejected() public {
        (bytes32 h, IntentSettler.Params memory p) = _open(100 * U);
        _solve(h, p);
        vm.prank(SOLVER);
        vm.expectRevert(IntentSettler.AlreadyFilled.selector);
        settlerArb.fill(p);
    }

    function test_expiredFillRejected() public {
        (, IntentSettler.Params memory p) = _open(100 * U);
        vm.warp(p.deadline + 1);
        vm.prank(SOLVER);
        vm.expectRevert(IntentSettler.Expired.selector);
        settlerArb.fill(p);
    }

    function test_fillOnWrongChainRejected() public {
        (, IntentSettler.Params memory p) = _open(100 * U);
        vm.prank(SOLVER);
        vm.expectRevert(IntentSettler.WrongDestination.selector);
        settlerBase.fill(p);
    }

    function test_repayOnlyOnce() public {
        (bytes32 h, IntentSettler.Params memory p) = _open(100 * U);
        _solve(h, p);
        mbBase.processNextInboundMessage();
        settlerBase.repay(h);
        vm.expectRevert(IntentSettler.NotFilled.selector);
        settlerBase.repay(h);
    }

    function test_cannotSettleWithMoreThanArrived() public {
        (bytes32 h, IntentSettler.Params memory p) = _open(100 * U);
        _solve(h, p);
        vm.prank(SOLVER);
        vm.expectRevert(BushidoFeeVault.InsufficientBucket.selector);
        vaultArb.settleFillFromBalance(h, 100_250_000); // repayment hasn't arrived yet
    }

    // ----------------------------------------------------------------- message auth
    function test_onlyMailboxCanDeliver() public {
        vm.prank(STRANGER);
        vm.expectRevert(IntentSettler.NotMailbox.selector);
        settlerBase.handle(ARB, bytes32(uint256(uint160(address(settlerArb)))), abi.encode(bytes32(0), SOLVER));
    }

    function test_rejectsConfirmationFromUnenrolledSettler() public {
        (bytes32 h, IntentSettler.Params memory p) = _open(100 * U);
        IntentSettler rogue = new IntentSettler(IHyperlaneMailbox(address(mbArb)), IWarpRoute(address(synthetic)), address(this));
        rogue.setPeer(BASE, address(settlerBase), address(0));
        // rogue "fills" by paying nothing real: give it allowance for the transfer to succeed
        vm.prank(SOLVER);
        vaultArb.drawForFill(h, p.amountOut, true);
        vm.prank(SOLVER);
        synthetic.approve(address(rogue), type(uint256).max);
        vm.prank(SOLVER);
        rogue.fill(p);
        bytes32 rogueSender = bytes32(uint256(uint160(address(rogue))));
        vm.expectRevert(abi.encodeWithSelector(IntentSettler.UnauthorizedSender.selector, ARB, rogueSender));
        mbBase.processNextInboundMessage();
        _eq(_status(h), 1, "order untouched");
    }

    function test_unknownDestinationRejected() public {
        vm.prank(USER);
        vm.expectRevert(abi.encodeWithSelector(IntentSettler.UnknownDomain.selector, uint32(97)));
        settlerBase.open(97, RECIPIENT, 1 * U, uint64(block.timestamp + 1));
    }
}
