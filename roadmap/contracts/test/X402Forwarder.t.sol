// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BushidoFeeVault, IERC20} from "../src/BushidoFeeVault.sol";
import {X402Forwarder} from "../src/X402Forwarder.sol";
import {MockUSDC} from "./mocks/MockUSDC.sol";
import {vm} from "./mocks/Vm.sol";

contract X402ForwarderTest {
    uint256 constant USDC = 1e6;
    uint256 constant JOB_FEE = 10_000; // 0.01 USDC
    uint256 constant MIN_FLUSH = 1 * USDC; // forward in >= 1 USDC batches (100 jobs)

    address constant OWNER = address(0xB051D0);
    address constant FACILITATOR = address(0xFAC);
    address constant KEEPER = address(0xEE9E5);
    address constant STRANGER = address(0xBAD);
    uint256 constant AGENT_KEY = 0xA11CE;

    MockUSDC usdc;
    BushidoFeeVault vault;
    X402Forwarder fwd;
    address agent;

    function setUp() public {
        vm.warp(1_700_000_000);
        usdc = new MockUSDC();
        vault = new BushidoFeeVault(IERC20(address(usdc)), OWNER, 6_250 * USDC, 25_000 * USDC, 500 * USDC);
        fwd = new X402Forwarder(vault, OWNER, MIN_FLUSH);
        vm.prank(OWNER);
        vault.setCollector(address(fwd), true);

        agent = vm.addr(AGENT_KEY);
        usdc.mint(agent, 1_000 * USDC);
    }

    // ---------------------------------------------------------------- helpers
    function _eq(uint256 a, uint256 b, string memory m) internal pure {
        require(a == b, m);
    }

    /// @dev Paying agent signs an EIP-3009 authorization; facilitator submits it (x402 "exact" scheme).
    function _pay(uint256 value, bytes32 nonce) internal {
        uint256 validAfter = block.timestamp - 1;
        uint256 validBefore = block.timestamp + 60;
        bytes32 digest = usdc.authorizationDigest(agent, address(fwd), value, validAfter, validBefore, nonce);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(AGENT_KEY, digest);
        vm.prank(FACILITATOR);
        usdc.transferWithAuthorization(agent, address(fwd), value, validAfter, validBefore, nonce, v, r, s);
    }

    function _payJobs(uint256 n) internal {
        for (uint256 i = 0; i < n; i++) {
            _pay(JOB_FEE, keccak256(abi.encode("job", i)));
        }
    }

    // ------------------------------------------------------------------ tests
    function test_wiring() public view {
        require(address(fwd.usdc()) == address(usdc), "usdc");
        require(address(fwd.vault()) == address(vault), "vault");
        require(vault.isCollector(address(fwd)), "collector");
    }

    function test_endToEnd_x402PaymentsFlowIntoVaultSplit() public {
        _payJobs(100); // 100 jobs x 0.01 = 1 USDC
        _eq(fwd.pending(), 1 * USDC, "batched at payTo");
        require(fwd.flushable(), "flushable");

        vm.prank(KEEPER);
        uint256 sent = fwd.flush();

        _eq(sent, 1 * USDC, "flushed amount");
        _eq(fwd.pending(), 0, "emptied");
        _eq(vault.inventory(), 700_000, "70% inventory");
        _eq(vault.reserve(), 100_000, "10% reserve");
        _eq(vault.ops(), 200_000, "20% ops");
        _eq(vault.totalCollected(BushidoFeeVault.Source.X402), 1 * USDC, "tagged X402");
        _eq(fwd.totalForwarded(), 1 * USDC, "total");
        _eq(fwd.flushCount(), 1, "count");
        _eq(usdc.balanceOf(address(vault)), vault.accounted(), "vault invariant");
    }

    function test_replayedAuthorizationRejected() public {
        _pay(JOB_FEE, "n1");
        uint256 validAfter = block.timestamp - 1;
        uint256 validBefore = block.timestamp + 60;
        bytes32 digest = usdc.authorizationDigest(agent, address(fwd), JOB_FEE, validAfter, validBefore, "n1");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(AGENT_KEY, digest);
        vm.expectRevert(bytes("auth used"));
        usdc.transferWithAuthorization(agent, address(fwd), JOB_FEE, validAfter, validBefore, "n1", v, r, s);
    }

    function test_flushBelowMinReverts() public {
        _payJobs(99); // 0.99 USDC
        require(!fwd.flushable(), "not flushable");
        vm.expectRevert(abi.encodeWithSelector(X402Forwarder.BelowMinFlush.selector, 990_000, MIN_FLUSH));
        fwd.flush();
    }

    function test_flushEmptyRevertsEvenWithZeroMin() public {
        vm.prank(OWNER);
        fwd.setMinFlush(0);
        vm.expectRevert(abi.encodeWithSelector(X402Forwarder.BelowMinFlush.selector, 0, 0));
        fwd.flush();
    }

    function test_flushFailsIfCollectorRevoked() public {
        _payJobs(100);
        vm.prank(OWNER);
        vault.setCollector(address(fwd), false);
        vm.expectRevert(BushidoFeeVault.NotCollector.selector);
        fwd.flush();
        _eq(fwd.pending(), 1 * USDC, "funds stay put");
    }

    function test_multipleBatchesAccumulate() public {
        _payJobs(100);
        fwd.flush();
        _pay(5 * USDC, "big");
        fwd.flush();
        _eq(fwd.totalForwarded(), 6 * USDC, "total");
        _eq(vault.totalCollected(BushidoFeeVault.Source.X402), 6 * USDC, "vault total");
        _eq(fwd.flushCount(), 2, "count");
    }

    function test_directTransferAlsoForwarded() public {
        // A plain USDC transfer to payTo (non-x402) still ends up split by the vault.
        vm.prank(agent);
        usdc.transfer(address(fwd), 2 * USDC);
        fwd.flush();
        _eq(vault.totalCollected(BushidoFeeVault.Source.X402), 2 * USDC, "forwarded");
    }

    function test_usdcCannotBeRescued() public {
        _payJobs(100);
        vm.prank(OWNER);
        vm.expectRevert(X402Forwarder.CannotRescueUsdc.selector);
        fwd.rescue(IERC20(address(usdc)), OWNER, 1);
    }

    function test_otherTokenRescuable() public {
        MockUSDC other = new MockUSDC();
        other.mint(address(fwd), 5);
        vm.prank(OWNER);
        fwd.rescue(IERC20(address(other)), OWNER, 5);
        _eq(other.balanceOf(OWNER), 5, "rescued");
    }

    function test_onlyOwnerAdmin() public {
        vm.startPrank(STRANGER);
        vm.expectRevert(X402Forwarder.NotOwner.selector);
        fwd.setMinFlush(0);
        vm.expectRevert(X402Forwarder.NotOwner.selector);
        fwd.transferOwnership(STRANGER);
        vm.stopPrank();
    }

    function test_twoStepOwnership() public {
        vm.prank(OWNER);
        fwd.transferOwnership(KEEPER);
        vm.prank(STRANGER);
        vm.expectRevert(X402Forwarder.NotOwner.selector);
        fwd.acceptOwnership();
        vm.prank(KEEPER);
        fwd.acceptOwnership();
        require(fwd.owner() == KEEPER, "new owner");
    }

    function testFuzz_flushConservesFunds(uint64 seed) public {
        uint256 amount = MIN_FLUSH + (uint256(seed) % (1_000 * USDC - MIN_FLUSH));
        vm.prank(agent);
        usdc.transfer(address(fwd), amount);
        fwd.flush();
        _eq(vault.inventory() + vault.reserve() + vault.ops(), amount, "conservation");
        _eq(usdc.balanceOf(address(vault)), vault.accounted(), "vault invariant");
        _eq(fwd.pending(), 0, "emptied");
    }
}
