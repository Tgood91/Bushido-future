// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {DojoPassDNA, IDojoPass, IHonor} from "../src/DojoPassDNA.sol";
import {DojoPassRenderer} from "../src/DojoPassRenderer.sol";
import {TestDojoPass} from "../src/testnet/TestDojoPass.sol";
import {TestHonor} from "../src/testnet/TestHonor.sol";
import {vm} from "../test/mocks/Vm.sol";

/// @notice Deploys the on-chain renderer and DojoPassDNA (paused).
///
/// Mainnet: point at the live contracts.
///   Base:  DOJO_PASS=0x6B6A971a0aaab34E70659E0723AD0dCe129f7D9c (no HONOR on Base: leave HONOR unset)
///   Monad: DOJO_PASS=0x2647faf3aaA708D0B9a110744790E1f637FCca53 HONOR=0x46D5F4924F833Cd4054A36eAEfa3bEca6cD92A7e
/// Testnets (Base Sepolia 84532, Monad testnet 10143): neither contract exists, so the
/// TestDojoPass / TestHonor stand-ins are deployed when DOJO_PASS / HONOR are unset.
/// The burner page uses DojoPassDNATestnetKit instead (one transaction).
///
/// Env:
///   DEPLOYER      address that signs (never a raw key in env)
///   OWNER         final owner
///   DOJO_PASS     registry (required off testnet)
///   HONOR         HONOR feed (optional; zero = none)
///   CONTRACT_URI  collection metadata URL (optional)
contract DeployDojoPassDNA {
    function run() external returns (DojoPassDNA dna, address registry, address honor, DojoPassRenderer renderer) {
        address deployer = vm.envAddress("DEPLOYER");
        address owner = vm.envAddress("OWNER");
        registry = vm.envOr("DOJO_PASS", address(0));
        honor = vm.envOr("HONOR", address(0));
        string memory contractURI = vm.envOr("CONTRACT_URI", string(""));

        bool testnet = block.chainid == 84532 || block.chainid == 10143;
        require(registry != address(0) || testnet, "DOJO_PASS required off testnet");

        vm.startBroadcast(deployer);
        if (registry == address(0)) registry = address(new TestDojoPass(owner, 0, address(0)));
        if (honor == address(0) && testnet) honor = address(new TestHonor(owner));
        renderer = new DojoPassRenderer();
        dna = new DojoPassDNA(IDojoPass(registry), IHonor(honor), renderer, owner, contractURI);
        vm.stopBroadcast();
    }
}
