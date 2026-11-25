// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {DojoPassDNA, IDojoPass, IHonor} from "../DojoPassDNA.sol";
import {DojoPassRenderer} from "../DojoPassRenderer.sol";
import {TestDojoPass} from "./TestDojoPass.sol";
import {TestHonor} from "./TestHonor.sol";

/// @notice TESTNET one-transaction setup for the burner page: deploys the registry and HONOR
/// stand-ins, the renderer and DojoPassDNA, grants `burner` a Dojo Pass, opens minting and hands
/// every contract to `burner`. The burner then mints with a second transaction (mint is msg.sender-bound).
contract DojoPassDNATestnetKit {
    TestDojoPass public immutable registry;
    TestHonor public immutable honor;
    DojoPassRenderer public immutable renderer;
    DojoPassDNA public immutable dna;

    constructor(address burner) {
        registry = new TestDojoPass(burner, 0, burner);
        honor = new TestHonor(burner);
        renderer = new DojoPassRenderer();
        dna = new DojoPassDNA(IDojoPass(address(registry)), IHonor(address(honor)), renderer, address(this), "");
        dna.unpause();
        dna.transferOwnership(burner);
    }
}
