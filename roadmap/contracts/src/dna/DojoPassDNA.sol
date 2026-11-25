// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

import "./IContractURI.sol";
import "./IDojoPassDNA.sol";

/// @title Dojo Pass DNA
/// @notice A living Dojo Pass, using Zerion DNA 1.0 (Ethereum 0x9322…848bf) as the template: a plain
/// ERC-721 whose traits live behind an owner-set base URI and are recomputed off-chain from the
/// holder's practice (trades recorded, virtues levelled), so the pass evolves without metadata writes.
///
/// Kept from Zerion DNA: Ownable, Pausable (deploys paused), contractURI, totalSupply, setBaseURI.
/// Changed for the Dojo Pass:
///  - mint is gated on the live Dojo Pass registry and costs `mintPrice` (0.0001 ether at deploy);
///  - tokenId = uint160(holder): one pass per wallet, mapping 1:1 to the address-keyed trait service;
///  - soulbound (ERC-5192): a discipline record is earned, not traded; holder may burn, owner may
///    burn only passes whose registry pass was revoked;
///  - ERC-4906 refresh events; plain _mint (a token that never moves needs no receiver callback).
/// Dropped: sequential ids, the OpenSea proxy registry (no code on Base/Monad, would revert).
contract DojoPassDNA is Ownable, Pausable, ERC721, IContractURI, IERC5192, IDojoPassDNA {
    /// @notice The live Dojo Pass registry on this chain.
    IDojoPass public immutable dojoPass;

    /// @inheritdoc IContractURI
    string public override contractURI;

    /// @inheritdoc IDojoPassDNA
    uint256 public override totalSupply;

    /// @inheritdoc IDojoPassDNA
    uint256 public override mintPrice = 0.0001 ether;

    // Prefix of each tokenURI
    string internal baseURI;

    /// @notice Creates Dojo Pass DNA for `registry` (paused, like Zerion DNA)
    constructor(IDojoPass registry) ERC721("Dojo Pass DNA", "DOJODNA") {
        if (address(registry) == address(0)) revert ZeroAddress();
        dojoPass = registry;
        _pause();
    }

    // ------------------------------------------------------------------ metadata

    /// @inheritdoc IDojoPassDNA
    function setBaseURI(string memory newBaseURI) external override onlyOwner {
        baseURI = newBaseURI;
        emit BatchMetadataUpdate(0, type(uint256).max);
    }

    /// @inheritdoc IDojoPassDNA
    function setContractURI(string memory newContractURI) external override onlyOwner {
        contractURI = newContractURI;
    }

    /// @inheritdoc IDojoPassDNA
    function refreshMetadata(uint256 tokenId) external override {
        address holder = ownerOf(tokenId);
        if (_msgSender() != holder && _msgSender() != owner()) revert NotHolder();
        emit MetadataUpdate(tokenId);
    }

    /// @inheritdoc ERC721
    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }

    // ------------------------------------------------------------------ mint / burn

    /// @inheritdoc IDojoPassDNA
    function mint() external payable override whenNotPaused {
        if (msg.value != mintPrice) revert WrongMintPrice(msg.value, mintPrice);
        if (!dojoPass.hasDojoPass(_msgSender())) revert NoDojoPass();
        uint256 tokenId = tokenIdOf(_msgSender());
        _mint(_msgSender(), tokenId); // reverts "token already minted": one per wallet
        unchecked {
            ++totalSupply;
        }
        emit Locked(tokenId);
    }

    /// @inheritdoc IDojoPassDNA
    function burn() external override {
        uint256 tokenId = tokenIdOf(_msgSender());
        if (_ownerOf(tokenId) != _msgSender()) revert NotHolder();
        _burnPass(tokenId);
    }

    /// @inheritdoc IDojoPassDNA
    function burnRevoked(address holder) external override onlyOwner {
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

    /// @inheritdoc IDojoPassDNA
    function tokenIdOf(address holder) public pure override returns (uint256) {
        return uint256(uint160(holder));
    }

    // ------------------------------------------------------------------ soulbound

    /// @inheritdoc IERC5192
    function locked(uint256 tokenId) external view override returns (bool) {
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

    function approve(address, uint256) public pure override(ERC721, IERC721) {
        revert Soulbound();
    }

    function setApprovalForAll(address, bool) public pure override(ERC721, IERC721) {
        revert Soulbound();
    }

    // ------------------------------------------------------------------ fees + admin

    /// @inheritdoc IDojoPassDNA
    function setMintPrice(uint256 newPrice) external override onlyOwner {
        mintPrice = newPrice;
        emit MintPriceSet(newPrice);
    }

    /// @inheritdoc IDojoPassDNA
    function withdraw() external override onlyOwner {
        uint256 amount = address(this).balance;
        (bool ok,) = payable(owner()).call{value: amount}("");
        if (!ok) revert WithdrawFailed();
        emit Withdrawn(owner(), amount);
    }

    /// @inheritdoc IDojoPassDNA
    function pause() external override onlyOwner {
        _pause();
    }

    /// @inheritdoc IDojoPassDNA
    function unpause() external override onlyOwner {
        _unpause();
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC721, IERC165)
        returns (bool)
    {
        return interfaceId == type(IContractURI).interfaceId || interfaceId == type(IERC5192).interfaceId
            || interfaceId == bytes4(0x49064906) // ERC-4906
            || super.supportsInterface(interfaceId);
    }
}
