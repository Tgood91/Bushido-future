// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";

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

/// @title Dojo Pass DNA
/// @notice A living, soulbound edition of the Dojo Pass. Modelled on Zerion DNA
/// (0x9322…848bf): a plain ERC-721 whose metadata is served from an owner-set
/// base URI and recomputed off-chain from the holder's practice.
///
/// Differences from Zerion DNA:
///  - Mint is gated on the existing Dojo Pass registry (earned, never bought here; no fee).
///  - tokenId = uint160(holder): one pass per wallet, and it maps 1:1 to the
///    address-keyed metadata backend.
///  - Soulbound (ERC-5192): no transfers or approvals. Holder may burn; owner may
///    burn only when the registry pass has been revoked.
///  - ERC-4906 events so marketplaces know to re-fetch metadata.
///  - No OpenSea proxy registry (2022 mainnet-only address).
contract DojoPassDNA is ERC721, Ownable, Pausable, IERC5192 {
    /// @notice The live Dojo Pass registry on this chain.
    IDojoPass public immutable dojoPass;

    /// @notice Collection-level metadata (OpenSea convention).
    string public contractURI;

    uint256 public totalSupply;

    string private baseURI_;

    // ERC-4906
    event MetadataUpdate(uint256 tokenId);
    event BatchMetadataUpdate(uint256 fromTokenId, uint256 toTokenId);

    error NoDojoPass();
    error Soulbound();
    error PassStillActive();
    error NotHolder();
    error ZeroAddress();

    constructor(IDojoPass registry, address owner_, string memory baseURI, string memory contractURI_)
        ERC721("Dojo Pass DNA", "DOJODNA")
    {
        if (address(registry) == address(0) || owner_ == address(0)) revert ZeroAddress();
        dojoPass = registry;
        baseURI_ = baseURI;
        contractURI = contractURI_;
        _transferOwnership(owner_);
        _pause(); // like Zerion DNA: deploy quietly, unpause to open minting
    }

    // ------------------------------------------------------------------ mint / burn

    /// @notice Mint your Dojo Pass DNA. Requires a Dojo Pass on this chain's registry.
    function mint() external whenNotPaused returns (uint256 tokenId) {
        if (!dojoPass.hasDojoPass(msg.sender)) revert NoDojoPass();
        tokenId = tokenIdOf(msg.sender);
        _mint(msg.sender, tokenId); // reverts if already minted: one per wallet
        unchecked {
            ++totalSupply;
        }
        emit Locked(tokenId);
    }

    /// @notice Holder burns their own pass.
    function burn() external {
        uint256 tokenId = tokenIdOf(msg.sender);
        if (_ownerOf(tokenId) != msg.sender) revert NotHolder();
        _burnPass(tokenId);
    }

    /// @notice Owner removes a pass whose registry pass was revoked. Cannot touch active passes.
    function burnRevoked(address holder) external onlyOwner {
        if (dojoPass.hasDojoPass(holder)) revert PassStillActive();
        uint256 tokenId = tokenIdOf(holder);
        if (_ownerOf(tokenId) != holder) revert NotHolder();
        _burnPass(tokenId);
    }

    function _burnPass(uint256 tokenId) private {
        _burn(tokenId);
        unchecked {
            --totalSupply;
        }
    }

    // ------------------------------------------------------------------ metadata

    /// @notice Point every token at the metadata backend. Emits ERC-4906 so marketplaces refresh.
    function setBaseURI(string calldata newBaseURI) external onlyOwner {
        baseURI_ = newBaseURI;
        emit BatchMetadataUpdate(0, type(uint256).max);
    }

    function setContractURI(string calldata newContractURI) external onlyOwner {
        contractURI = newContractURI;
    }

    /// @notice Ask marketplaces to re-fetch one pass after it evolved. Holder or owner only.
    function refreshMetadata(uint256 tokenId) external {
        address holder = ownerOf(tokenId);
        if (msg.sender != holder && msg.sender != owner()) revert NotHolder();
        emit MetadataUpdate(tokenId);
    }

    /// @dev tokenURI = baseURI + decimal tokenId (OpenZeppelin default).
    function _baseURI() internal view override returns (string memory) {
        return baseURI_;
    }

    /// @notice The only tokenId `holder` can ever own.
    function tokenIdOf(address holder) public pure returns (uint256) {
        return uint256(uint160(holder));
    }

    // ------------------------------------------------------------------ soulbound

    /// @inheritdoc IERC5192
    function locked(uint256 tokenId) external view returns (bool) {
        _requireMinted(tokenId);
        return true;
    }

    function _beforeTokenTransfer(address from, address to, uint256 firstTokenId, uint256 batchSize)
        internal
        override
    {
        if (from != address(0) && to != address(0)) revert Soulbound();
        super._beforeTokenTransfer(from, to, firstTokenId, batchSize);
    }

    function approve(address, uint256) public pure override {
        revert Soulbound();
    }

    function setApprovalForAll(address, bool) public pure override {
        revert Soulbound();
    }

    // ------------------------------------------------------------------ admin

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return interfaceId == type(IERC5192).interfaceId // 0xb45a3c0e
            || interfaceId == bytes4(0x49064906) // ERC-4906
            || super.supportsInterface(interfaceId);
    }
}
