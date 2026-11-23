// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {CCIPLocalSimulator} from "@chainlink/local/src/ccip/CCIPLocalSimulator.sol";
import {BurnMintERC677Helper} from "@chainlink/local/src/ccip/BurnMintERC677Helper.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/contracts/interfaces/IRouterClient.sol";
import {Client} from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";
import {BushidoFeeVault, IERC20} from "../src/BushidoFeeVault.sol";
import {InventoryBridge} from "../src/ccip/InventoryBridge.sol";
import {vm} from "./mocks/Vm.sol";

/// @notice CCIP inventory rebalancing between two vaults (think Base <-> Monad) using Chainlink Local.
///         The local router delivers the message and tokens synchronously, in the same transaction.
contract InventoryBridgeTest {
    uint256 constant T = 1e18; // CCIP-BnM test token has 18 decimals
    address constant OWNER = address(0xB051D0);
    address constant KEEPER = address(0xEE9E5);
    address constant STRANGER = address(0xBAD);

    CCIPLocalSimulator sim;
    uint64 sel;
    IRouterClient router;
    BurnMintERC677Helper bnm;

    BushidoFeeVault vaultA; // "Base"
    BushidoFeeVault vaultB; // "Monad"
    InventoryBridge bridgeA;
    InventoryBridge bridgeB;

    function setUp() public {
        sim = new CCIPLocalSimulator();
        (sel, router,,,, bnm,) = sim.configuration();

        vaultA = new BushidoFeeVault(IERC20(address(bnm)), OWNER, 6 * T, 25 * T, 1 * T);
        vaultB = new BushidoFeeVault(IERC20(address(bnm)), OWNER, 6 * T, 25 * T, 1 * T);
        bridgeA = new InventoryBridge(address(router), vaultA, OWNER, 20 * T);
        bridgeB = new InventoryBridge(address(router), vaultB, OWNER, 20 * T);

        bytes memory args = Client._argsToBytes(Client.GenericExtraArgsV2({gasLimit: 300_000, allowOutOfOrderExecution: true}));
        vm.startPrank(OWNER);
        vaultA.setRebalancer(address(bridgeA));
        vaultB.setRebalancer(address(bridgeB));
        vaultA.setSolver(OWNER);
        bridgeA.setPeer(sel, address(bridgeB), args);
        bridgeB.setPeer(sel, address(bridgeA), args);
        bridgeA.setKeeper(KEEPER);
        vm.stopPrank();

        _seed(vaultA, 10);
    }

    function _seed(BushidoFeeVault v, uint256 n) internal {
        for (uint256 i = 0; i < n; i++) bnm.drip(address(this));
        bnm.approve(address(v), n * T);
        v.seedInventory(n * T);
    }

    function _eq(uint256 a, uint256 b, string memory m) internal pure {
        require(a == b, m);
    }

    // ------------------------------------------------------------------ happy path
    function test_rebalanceMovesInventoryAcrossChains() public {
        vm.prank(OWNER);
        bridgeA.rebalance(sel, 4 * T);
        _eq(vaultA.inventory(), 6 * T, "source vault down");
        _eq(vaultB.inventory(), 4 * T, "dest vault up");
        _eq(bridgeA.sentTo(sel), 4 * T, "sent tracked");
        _eq(bridgeB.receivedFrom(sel), 4 * T, "received tracked");
        _eq(bnm.balanceOf(address(bridgeA)) + bnm.balanceOf(address(bridgeB)), 0, "bridges hold nothing");
        _eq(bnm.balanceOf(address(vaultA)), vaultA.accounted(), "A invariant");
        _eq(bnm.balanceOf(address(vaultB)), vaultB.accounted(), "B invariant");
    }

    function test_keeperCanRebalanceAndRoundTrip() public {
        vm.prank(KEEPER);
        bridgeA.rebalance(sel, 3 * T);
        vm.prank(OWNER);
        bridgeB.rebalance(sel, 1 * T); // back the other way
        _eq(vaultA.inventory(), 8 * T, "A after round trip");
        _eq(vaultB.inventory(), 2 * T, "B after round trip");
    }

    function test_arrivalCanGraduateDestinationVault() public {
        vm.prank(OWNER);
        bridgeA.rebalance(sel, 6 * T);
        vaultB.advancePhase(); // 6 >= SELF_SOLVE threshold on B
        _eq(uint8(vaultB.phase()), 1, "B graduated on bridged inventory");
    }

    // ------------------------------------------------------------------ guardrails
    function test_onlyOwnerOrKeeper() public {
        vm.prank(STRANGER);
        vm.expectRevert(InventoryBridge.NotOwnerOrKeeper.selector);
        bridgeA.rebalance(sel, 1 * T);
    }

    function test_onlyBridgeCanPullFromVault() public {
        vm.prank(STRANGER);
        vm.expectRevert(BushidoFeeVault.NotRebalancer.selector);
        vaultA.sendInventory(1 * T);
    }

    function test_maxPerTransfer() public {
        vm.prank(OWNER);
        vm.expectRevert(abi.encodeWithSelector(InventoryBridge.OverMaxPerTransfer.selector, 21 * T, 20 * T));
        bridgeA.rebalance(sel, 21 * T);
    }

    function test_unknownDestination() public {
        vm.prank(OWNER);
        vm.expectRevert(abi.encodeWithSelector(InventoryBridge.UnknownPeer.selector, uint64(123)));
        bridgeA.rebalance(123, 1 * T);
    }

    function test_cannotShipMoreThanIdleInventory() public {
        vm.prank(OWNER);
        vm.expectRevert(BushidoFeeVault.InsufficientInventory.selector);
        bridgeA.rebalance(sel, 11 * T);
    }

    function test_utilisationCapBlocksRebalance() public {
        vaultA.advancePhase(); // capital 10 -> SELF_SOLVE
        vm.prank(OWNER);
        vaultA.drawForFill("f", 1 * T, false); // outstanding 1, capital 10
        // shipping 9 leaves capital 1 with 1 outstanding = 100% > 80% cap
        vm.prank(OWNER);
        vm.expectRevert(BushidoFeeVault.UtilizationExceeded.selector);
        bridgeA.rebalance(sel, 9 * T);
    }

    function test_rebalancingAwayDemotesPhase() public {
        vaultA.advancePhase(); // SELF_SOLVE at capital 10
        vm.prank(OWNER);
        bridgeA.rebalance(sel, 5 * T); // capital 5 < 6
        _eq(uint8(vaultA.phase()), 0, "demoted to ROUTING");
    }

    function test_rejectsSpoofedSourceBridge() public {
        // A rogue bridge on the "same chain" points at B, but B only trusts bridgeA for this selector.
        BushidoFeeVault rogueVault = new BushidoFeeVault(IERC20(address(bnm)), address(this), 6 * T, 25 * T, 1 * T);
        InventoryBridge rogue = new InventoryBridge(address(router), rogueVault, address(this), 20 * T);
        rogueVault.setRebalancer(address(rogue));
        rogue.setPeer(sel, address(bridgeB), Client._argsToBytes(Client.GenericExtraArgsV2({gasLimit: 300_000, allowOutOfOrderExecution: true})));
        _seed(rogueVault, 2);

        bytes memory inner = abi.encodeWithSelector(InventoryBridge.UnauthorizedSender.selector, sel, address(rogue));
        vm.expectRevert(abi.encodeWithSignature("ReceiverError(bytes)", inner));
        rogue.rebalance(sel, 1 * T);
        _eq(vaultB.inventory(), 0, "nothing credited");
    }

    function test_ccipReceiveOnlyFromRouter() public {
        Client.EVMTokenAmount[] memory none = new Client.EVMTokenAmount[](0);
        Client.Any2EVMMessage memory m = Client.Any2EVMMessage({
            messageId: bytes32(0), sourceChainSelector: sel, sender: abi.encode(address(bridgeA)), data: abi.encode(uint256(1)), destTokenAmounts: none
        });
        vm.prank(STRANGER);
        vm.expectRevert(abi.encodeWithSignature("InvalidRouter(address)", STRANGER));
        bridgeB.ccipReceive(m);
    }

    function test_twoStepOwnership() public {
        vm.prank(OWNER);
        bridgeA.transferOwnership(KEEPER);
        _eq(uint160(bridgeA.owner()), uint160(OWNER), "unchanged until accepted");
        vm.prank(KEEPER);
        bridgeA.acceptOwnership();
        _eq(uint160(bridgeA.owner()), uint160(KEEPER), "accepted");
    }
}
