// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/// @notice Collection-level metadata URL (OpenSea convention), as in Zerion DNA.
interface IContractURI is IERC165 {
    function contractURI() external view returns (string memory);
}
