// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// Pulls Hyperlane contracts into the build so their artifacts can be exported for the solver/deploy scripts.
import {TestIsm} from "@hyperlane-xyz/core/contracts/test/TestIsm.sol";
import {HypERC20} from "@hyperlane-xyz/core/contracts/token/HypERC20.sol";
import {HypERC20Collateral} from "@hyperlane-xyz/core/contracts/token/HypERC20Collateral.sol";
