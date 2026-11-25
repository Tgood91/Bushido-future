// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {DojoPassDNA} from "../src/dna/DojoPassDNA.sol";
import {IDojoPass} from "../src/dna/IDojoPassDNA.sol";
import {TestDojoPass} from "../src/testnet/TestDojoPass.sol";
import {vm} from "../test/mocks/Vm.sol";

/// @notice Deploys DojoPassDNA (paused, like Zerion DNA; OPEN=1 unpauses in the same run).
/// DOJO_PASS is the live registry (Base 0x6B6A971a0aaab34E70659E0723AD0dCe129f7D9c,
/// Monad 0x2647faf3aaA708D0B9a110744790E1f637FCca53). On testnets (84532, 10143, 31337) it may be
/// unset: a TestDojoPass stand-in is deployed and DEPLOYER gets a pass. Optional BASE_URI, CONTRACT_URI.
/// The burner page (testnet/, step D1) does the same from the wallet. Never a raw key in env.
contract DeployDojoPassDNA {
    function run() external returns (DojoPassDNA dna, address registry) {
        address deployer = vm.envAddress("DEPLOYER");
        registry = vm.envOr("DOJO_PASS", address(0));
        string memory baseURI = vm.envOr("BASE_URI", string(""));
        string memory contractURI = vm.envOr("CONTRACT_URI", string(""));
        bool open = vm.envOr("OPEN", uint256(0)) == 1;
        bool testnet = block.chainid == 84532 || block.chainid == 10143 || block.chainid == 31337;
        require(registry != address(0) || testnet, "DOJO_PASS required off testnet");

        vm.startBroadcast(deployer);
        if (registry == address(0)) registry = address(new TestDojoPass(deployer, 0, deployer));
        dna = new DojoPassDNA(IDojoPass(registry));
        if (bytes(baseURI).length != 0) dna.setBaseURI(baseURI);
        if (bytes(contractURI).length != 0) dna.setContractURI(contractURI);
        if (open) dna.unpause();
        vm.stopBroadcast();
    }
}
