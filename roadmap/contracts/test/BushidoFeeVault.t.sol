// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BushidoFeeVault, IERC20} from "../src/BushidoFeeVault.sol";
import {MockUSDC} from "./mocks/MockUSDC.sol";
import {vm} from "./mocks/Vm.sol";

contract BushidoFeeVaultTest {
    uint256 constant USDC = 1e6;
    uint256 constant SELF_SOLVE = 6_250 * USDC;
    uint256 constant BRIDGE = 25_000 * USDC;
    uint256 constant MAX_FILL = 500 * USDC;

    address constant OWNER = address(0xB051D0);
    address constant SOLVER = address(0x50173);
    address constant COLLECTOR = address(0x402);
    address constant STRANGER = address(0xBAD);

    MockUSDC usdc;
    BushidoFeeVault vault;

    function setUp() public {
        usdc = new MockUSDC();
        vault = new BushidoFeeVault(IERC20(address(usdc)), OWNER, SELF_SOLVE, BRIDGE, MAX_FILL);
        vm.startPrank(OWNER);
        vault.setSolver(SOLVER);
        vault.setCollector(COLLECTOR, true);
        vm.stopPrank();

        usdc.mint(COLLECTOR, 1_000_000 * USDC);
        usdc.mint(SOLVER, 1_000_000 * USDC);
        usdc.mint(address(this), 1_000_000 * USDC);
        vm.prank(COLLECTOR);
        usdc.approve(address(vault), type(uint256).max);
        vm.prank(SOLVER);
        usdc.approve(address(vault), type(uint256).max);
        usdc.approve(address(vault), type(uint256).max);
    }

    // ---------------------------------------------------------------- helpers
    function _eq(uint256 a, uint256 b, string memory m) internal pure {
        require(a == b, m);
    }

    function _phase() internal view returns (uint8) {
        return uint8(vault.phase());
    }

    function _toSelfSolve() internal {
        vault.seedInventory(SELF_SOLVE);
        vault.advancePhase();
    }

    function _toBridge() internal {
        vault.seedInventory(BRIDGE);
        vault.advancePhase();
        vault.advancePhase();
    }

    function _invariant() internal view {
        require(usdc.balanceOf(address(vault)) >= vault.accounted(), "accounting invariant");
    }

    // ------------------------------------------------------------- fee split
    function test_feeSplitDefault70_10_20() public {
        vm.prank(COLLECTOR);
        vault.collectFee(BushidoFeeVault.Source.EXECUTION, 100 * USDC);
        _eq(vault.inventory(), 70 * USDC, "inventory");
        _eq(vault.reserve(), 10 * USDC, "reserve");
        _eq(vault.ops(), 20 * USDC, "ops");
        _eq(vault.totalCollected(BushidoFeeVault.Source.EXECUTION), 100 * USDC, "total");
        _invariant();
    }

    function test_x402MicroFeeRoundingGoesToOps() public {
        vm.prank(COLLECTOR);
        vault.collectFee(BushidoFeeVault.Source.X402, 10_000); // 0.01 USDC
        _eq(vault.inventory() + vault.reserve() + vault.ops(), 10_000, "no dust lost");
        _invariant();
    }

    function testFuzz_splitConservesFunds(uint96 seed) public {
        uint256 amount = 1 + (uint256(seed) % (1_000_000 * USDC - 1)); // bound, don't reject
        vm.prank(COLLECTOR);
        vault.collectFee(BushidoFeeVault.Source.EXECUTION, amount);
        _eq(vault.inventory() + vault.reserve() + vault.ops(), amount, "conservation");
        _invariant();
    }

    function test_strangerCannotCollect() public {
        vm.prank(STRANGER);
        vm.expectRevert(BushidoFeeVault.NotCollector.selector);
        vault.collectFee(BushidoFeeVault.Source.EXECUTION, 1);
    }

    function test_collectorCannotSpoofSolverSpread() public {
        vm.prank(COLLECTOR);
        vm.expectRevert(BushidoFeeVault.BadSource.selector);
        vault.collectFee(BushidoFeeVault.Source.SOLVER_SPREAD, 1);
    }

    function test_retentionFloorEnforced() public {
        vm.prank(OWNER);
        vm.expectRevert(BushidoFeeVault.BadSplit.selector);
        vault.setSplit(4_000, 1_000, 5_000);
    }

    // ------------------------------------------------------------- graduation
    function test_cannotAdvanceBelowThreshold() public {
        vault.seedInventory(SELF_SOLVE - 1);
        vm.expectRevert(abi.encodeWithSelector(BushidoFeeVault.ThresholdNotMet.selector, SELF_SOLVE - 1, SELF_SOLVE));
        vault.advancePhase();
    }

    function test_graduatesStepByStep() public {
        vault.seedInventory(BRIDGE);
        vault.advancePhase();
        _eq(_phase(), 1, "self-solve");
        vault.advancePhase();
        _eq(_phase(), 2, "bridge");
    }

    function test_feesAloneCanGraduate() public {
        // 70% retention: 6,250 / 0.7 = 8,928.58 USDC of fees needed
        vm.prank(COLLECTOR);
        vault.collectFee(BushidoFeeVault.Source.EXECUTION, 8_929 * USDC);
        vault.advancePhase();
        _eq(_phase(), 1, "graduated on fees");
    }

    function test_ownerCanOnlyDemote() public {
        _toSelfSolve();
        vm.prank(OWNER);
        vm.expectRevert(
            abi.encodeWithSelector(BushidoFeeVault.PhaseTooLow.selector, BushidoFeeVault.Phase.BRIDGE, BushidoFeeVault.Phase.SELF_SOLVE)
        );
        vault.demote(BushidoFeeVault.Phase.BRIDGE);
        vm.prank(OWNER);
        vault.demote(BushidoFeeVault.Phase.ROUTING);
        _eq(_phase(), 0, "demoted");
    }

    // ------------------------------------------------------------------ fills
    function test_noFillsWhileRouting() public {
        vault.seedInventory(SELF_SOLVE - 1);
        vm.prank(SOLVER);
        vm.expectRevert(
            abi.encodeWithSelector(BushidoFeeVault.PhaseTooLow.selector, BushidoFeeVault.Phase.SELF_SOLVE, BushidoFeeVault.Phase.ROUTING)
        );
        vault.drawForFill("a", 100 * USDC, false);
    }

    function test_crossChainNeedsBridgePhase() public {
        _toSelfSolve();
        vm.prank(SOLVER);
        vm.expectRevert(
            abi.encodeWithSelector(BushidoFeeVault.PhaseTooLow.selector, BushidoFeeVault.Phase.BRIDGE, BushidoFeeVault.Phase.SELF_SOLVE)
        );
        vault.drawForFill("x", 100 * USDC, true);
    }

    function test_onlySolverDraws() public {
        _toSelfSolve();
        vm.prank(STRANGER);
        vm.expectRevert(BushidoFeeVault.NotSolver.selector);
        vault.drawForFill("a", 100 * USDC, false);
    }

    function test_maxFillEnforced() public {
        _toSelfSolve();
        vm.prank(SOLVER);
        vm.expectRevert(abi.encodeWithSelector(BushidoFeeVault.FillTooLarge.selector, MAX_FILL + 1, MAX_FILL));
        vault.drawForFill("a", MAX_FILL + 1, false);
    }

    function test_fillIdCannotBeReused() public {
        _toSelfSolve();
        vm.startPrank(SOLVER);
        vault.drawForFill("a", 100 * USDC, false);
        vault.settleFill("a", 100 * USDC);
        vm.expectRevert(BushidoFeeVault.FillExists.selector);
        vault.drawForFill("a", 100 * USDC, false);
        vm.stopPrank();
    }

    function test_utilizationCap() public {
        // capital 1,000 with 80% cap => at most 800 outstanding
        vm.prank(OWNER);
        vault.setThresholds(1_000 * USDC, BRIDGE);
        vault.seedInventory(1_000 * USDC);
        vault.advancePhase();
        vm.startPrank(SOLVER);
        vault.drawForFill("a", 500 * USDC, false);
        vault.drawForFill("b", 300 * USDC, false);
        vm.expectRevert(BushidoFeeVault.UtilizationExceeded.selector);
        vault.drawForFill("c", 1, false);
        vm.stopPrank();
    }

    function test_dailyCapResetsNextDay() public {
        vm.prank(OWNER);
        vault.setRisk(MAX_FILL, 10_000, MAX_FILL, 15 minutes, 6 hours);
        _toSelfSolve();
        vm.startPrank(SOLVER);
        vault.drawForFill("a", MAX_FILL, false);
        vault.settleFill("a", MAX_FILL);
        vm.expectRevert(abi.encodeWithSelector(BushidoFeeVault.DailyCapExceeded.selector, MAX_FILL + 1, MAX_FILL));
        vault.drawForFill("b", 1, false);
        vm.warp(block.timestamp + 1 days);
        vault.drawForFill("b", 1, false);
        vm.stopPrank();
    }

    function test_settleProfitCompoundsIntoInventory() public {
        _toSelfSolve();
        uint256 before = vault.inventory();
        vm.startPrank(SOLVER);
        vault.drawForFill("a", 500 * USDC, false);
        vault.settleFill("a", 501 * USDC); // 1 USDC spread (20 bps)
        vm.stopPrank();
        _eq(vault.inventory(), before + 700_000, "70% of spread retained");
        _eq(vault.outstanding(), 0, "flat");
        _eq(vault.totalCollected(BushidoFeeVault.Source.SOLVER_SPREAD), 1 * USDC, "spread tracked");
        _invariant();
    }

    function test_lossCoveredByReserveFirst() public {
        vm.prank(COLLECTOR);
        vault.collectFee(BushidoFeeVault.Source.EXECUTION, 1_000 * USDC); // reserve = 100
        _toSelfSolve();
        uint256 inv = vault.inventory();
        vm.startPrank(SOLVER);
        vault.drawForFill("a", 500 * USDC, false);
        vault.settleFill("a", 450 * USDC); // 50 loss
        vm.stopPrank();
        _eq(vault.reserve(), 50 * USDC, "reserve absorbed");
        _eq(vault.inventory(), inv, "inventory whole");
        _eq(vault.totalLosses(), 0, "no uncovered loss");
        _invariant();
    }

    function test_defaultAfterTimeoutDemotesToRouting() public {
        _toBridge();
        vm.prank(SOLVER);
        vault.drawForFill("x", 500 * USDC, true);

        vm.warp(block.timestamp + 1 hours); // same-chain timeout passed, cross-chain not
        vm.prank(STRANGER);
        vm.expectRevert(BushidoFeeVault.NotTimedOut.selector);
        vault.markDefault("x");

        vm.warp(block.timestamp + 6 hours);
        vm.prank(STRANGER);
        vault.markDefault("x");
        _eq(_phase(), 0, "back to routing");
        _eq(vault.outstanding(), 0, "written off");
        _eq(vault.totalLosses(), 500 * USDC, "uncovered loss recorded");
        _invariant();
    }

    // ------------------------------------------------------------ withdrawals
    function test_opsWithdrawable() public {
        vm.prank(COLLECTOR);
        vault.collectFee(BushidoFeeVault.Source.EXECUTION, 100 * USDC);
        vm.prank(OWNER);
        vault.withdrawOps(OWNER, 20 * USDC);
        _eq(usdc.balanceOf(OWNER), 20 * USDC, "ops paid");
        _invariant();
    }

    function test_inventoryLockedOutsideRouting() public {
        _toSelfSolve();
        vm.prank(OWNER);
        vm.expectRevert(BushidoFeeVault.MustBeRoutingAndFlat.selector);
        vault.emergencyWithdraw(OWNER, 1, 0);
    }

    function test_cannotSwapSolverWithOpenFills() public {
        _toSelfSolve();
        vm.prank(SOLVER);
        vault.drawForFill("a", 100 * USDC, false);
        vm.prank(OWNER);
        vm.expectRevert(BushidoFeeVault.MustBeRoutingAndFlat.selector);
        vault.setSolver(STRANGER);
    }
}
