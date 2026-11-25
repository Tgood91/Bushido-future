// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

/// @notice Mirrors Zerion DNA's IZerionDNA, plus a mint price and fee withdrawal.
interface IDojoPassDNA is IERC721 {
    event MintPriceSet(uint256 price);
    event Withdrawn(address indexed to, uint256 amount);

    error WrongMintPrice(uint256 sent, uint256 price);
    error WithdrawFailed();

    /// @notice Sets the prefix of every tokenURI (tokenURI = baseURI + tokenId).
    function setBaseURI(string memory newBaseURI) external;

    function setContractURI(string memory newContractURI) external;

    /// @notice Mints the next token to the caller. Pays exactly `mintPrice`.
    function mint() external payable;

    function setMintPrice(uint256 newPrice) external;

    /// @notice Sends collected mint fees to the owner.
    function withdraw() external;

    function pause() external;

    function unpause() external;

    function totalSupply() external view returns (uint256);

    function mintPrice() external view returns (uint256);
}
