// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

/// @notice Read side of the live Dojo Pass registry (Base 0x6B6A…7D9c, Monad 0x2647…CA53).
/// Selectors verified against deployed bytecode on 2026-11-24.
interface IDojoPass {
    function hasDojoPass(address account) external view returns (bool);
}

/// @notice ERC-5192 minimal soulbound interface.
interface IERC5192 {
    event Locked(uint256 tokenId);
    event Unlocked(uint256 tokenId);

    function locked(uint256 tokenId) external view returns (bool);
}

/// @notice Dojo Pass DNA. Shape follows Zerion DNA's IZerionDNA; additions are marked.
interface IDojoPassDNA is IERC721 {
    // ERC-4906: tells marketplaces to re-fetch metadata (addition)
    event MetadataUpdate(uint256 tokenId);
    event BatchMetadataUpdate(uint256 fromTokenId, uint256 toTokenId);
    event MintPriceSet(uint256 price);
    event Withdrawn(address indexed to, uint256 amount);

    error WrongMintPrice(uint256 sent, uint256 price);
    error NoDojoPass();
    error Soulbound();
    error NotHolder();
    error PassStillActive();
    error WithdrawFailed();
    error ZeroAddress();

    /// @notice Prefix of every tokenURI: tokenURI = baseURI + tokenId (decimal uint160 of the holder).
    function setBaseURI(string memory newBaseURI) external;

    function setContractURI(string memory newContractURI) external;

    /// @notice Mint your pass. Requires a Dojo Pass on this chain's registry and exactly `mintPrice`.
    function mint() external payable;

    /// @notice Holder burns their own pass (addition).
    function burn() external;

    /// @notice Owner burns a pass whose registry pass was revoked (addition).
    function burnRevoked(address holder) external;

    /// @notice Ask marketplaces to re-fetch one pass after it evolved. Holder or owner (addition).
    function refreshMetadata(uint256 tokenId) external;

    function setMintPrice(uint256 newPrice) external;

    function withdraw() external;

    function pause() external;

    function unpause() external;

    function totalSupply() external view returns (uint256);

    function mintPrice() external view returns (uint256);

    function tokenIdOf(address holder) external pure returns (uint256);
}
