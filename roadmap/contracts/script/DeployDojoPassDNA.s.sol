// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {DojoPassDNA} from "../src/dna/DojoPassDNA.sol";
import {vm} from "../test/mocks/Vm.sol";

/// @notice Deploys DojoPassDNA (Zerion DNA clone, 0.0001 ether mint). Deployed paused, like Zerion;
/// with OPEN=1 it is unpaused in the same run. Optional BASE_URI / CONTRACT_URI.
/// The burner page (testnet/) does the same from the wallet; this script is for dry runs and
/// `--account`/`--ledger` deploys. Never a raw key in env.
///   DEPLOYER=0x.. forge script script/DeployDojoPassDNA.s.sol --rpc-url https://sepolia.base.org
contract DeployDojoPassDNA {
    function run() external returns (DojoPassDNA dna) {
        address deployer = vm.envAddress("DEPLOYER");
        string memory baseURI = vm.envOr("BASE_URI", string(""));
        string memory contractURI = vm.envOr("CONTRACT_URI", string(""));
        bool open = vm.envOr("OPEN", uint256(0)) == 1;

        vm.startBroadcast(deployer);
        dna = new DojoPassDNA();
        if (bytes(baseURI).length != 0) dna.setBaseURI(baseURI);
        if (bytes(contractURI).length != 0) dna.setContractURI(contractURI);
        if (open) dna.unpause();
        vm.stopBroadcast();
    }
}
