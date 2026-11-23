// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BushidoFeeVault, IERC20} from "../src/BushidoFeeVault.sol";
import {X402Forwarder} from "../src/X402Forwarder.sol";
import {vm} from "../test/mocks/Vm.sol";

/// @notice Deploys BushidoFeeVault + X402Forwarder and wires the forwarder as a fee collector.
/// Env:
///   USDC      Base USDC address (mainnet 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913,
///             Base Sepolia 0x036CbD53842c5426634e7929541eC2318f3dCF7e) - verify before use
///   DEPLOYER  address that signs (use --account / --ledger; never a raw key in env)
///   OWNER     final owner (multisig recommended); must call vault.acceptOwnership()
///   SELF_SOLVE_THRESHOLD, BRIDGE_THRESHOLD, MAX_FILL, MIN_FLUSH  (6-decimal USDC units, optional)
contract Deploy {
    function run() external returns (BushidoFeeVault vault, X402Forwarder fwd) {
        address usdc = vm.envAddress("USDC");
        address deployer = vm.envAddress("DEPLOYER");
        address owner = vm.envAddress("OWNER");
        uint256 selfSolve = vm.envOr("SELF_SOLVE_THRESHOLD", uint256(6_250e6));
        uint256 bridge = vm.envOr("BRIDGE_THRESHOLD", uint256(25_000e6));
        uint256 maxFill = vm.envOr("MAX_FILL", uint256(500e6));
        uint256 minFlush = vm.envOr("MIN_FLUSH", uint256(1e6));

        vm.startBroadcast(deployer);
        // deployer owns the vault briefly so it can whitelist the forwarder, then hands over
        vault = new BushidoFeeVault(IERC20(usdc), deployer, selfSolve, bridge, maxFill);
        fwd = new X402Forwarder(vault, owner, minFlush);
        vault.setCollector(address(fwd), true);
        if (owner != deployer) vault.transferOwnership(owner);
        vm.stopBroadcast();
    }
}
