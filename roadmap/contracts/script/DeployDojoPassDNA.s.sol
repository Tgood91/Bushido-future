// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {DojoPassDNA, IDojoPass} from "../src/DojoPassDNA.sol";
import {TestDojoPass} from "../src/testnet/TestDojoPass.sol";
import {vm} from "../test/mocks/Vm.sol";

/// @notice Deploys DojoPassDNA (paused). On testnets (Base Sepolia 84532, Monad testnet 10143)
/// the live Dojo Pass registry does not exist, so a TestDojoPass stand-in is deployed first
/// unless DOJO_PASS is given.
///
/// Env:
///   DEPLOYER      address that signs (burner via --account / page; never a raw key in env)
///   OWNER         final owner of DNA (and of the test registry)
///   DOJO_PASS     existing registry (optional on testnets; required on mainnet:
///                 Base 0x6B6A971a0aaab34E70659E0723AD0dCe129f7D9c, Monad 0x2647faf3aaA708D0B9a110744790E1f637FCca53)
///   BASE_URI      metadata base, e.g. https://<host>/api/dojo-pass/<chain>/token/
///   CONTRACT_URI  collection metadata URL (optional)
///   PASS_FEE_WEI  test registry fee (optional, default 0.001 ether)
///
/// Dry run (no broadcast), e.g.:
///   DEPLOYER=0x.. OWNER=0x.. BASE_URI=https://.../ forge script script/DeployDojoPassDNA.s.sol --rpc-url https://sepolia.base.org
contract DeployDojoPassDNA {
    function run() external returns (DojoPassDNA dna, address registry) {
        address deployer = vm.envAddress("DEPLOYER");
        address owner = vm.envAddress("OWNER");
        registry = vm.envOr("DOJO_PASS", address(0));
        string memory baseURI = vm.envOr("BASE_URI", string(""));
        string memory contractURI = vm.envOr("CONTRACT_URI", string(""));
        uint256 fee = vm.envOr("PASS_FEE_WEI", uint256(0.001 ether));

        bool testnet = block.chainid == 84532 || block.chainid == 10143;
        require(registry != address(0) || testnet, "DOJO_PASS required off testnet");
        require(bytes(baseURI).length != 0, "BASE_URI required");

        vm.startBroadcast(deployer);
        if (registry == address(0)) registry = address(new TestDojoPass(owner, fee));
        dna = new DojoPassDNA(IDojoPass(registry), owner, baseURI, contractURI);
        vm.stopBroadcast();
    }
}
