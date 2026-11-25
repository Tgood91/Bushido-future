// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {IDojoPassRenderer, PassState} from "./DojoPassRenderer.sol";

/// @notice Read side of the live Dojo Pass registry (Base 0x6B6A…7D9c, Monad 0x2647…CA53).
/// Selectors verified against deployed bytecode on 2026-11-24.
interface IDojoPass {
    function hasDojoPass(address account) external view returns (bool);
    function isPractitioner(address account) external view returns (bool);
}

/// @notice Read side of HONOR ("Bushido Honor", Monad 0x46D5…7A2e), the recordTrade feed.
/// Selectors verified against deployed bytecode on 2026-11-24.
interface IHonor {
    function tradeCount(address trader) external view returns (uint256);
    function honorScores(address trader) external view returns (uint256);
    /// @dev 5 static words: Gi, Yu, Jin, Rei, Makoto, each 0-10.
    function getVirtueScores(address trader) external view returns (uint256, uint256, uint256, uint256, uint256);
}

/// @notice ERC-5192 minimal soulbound interface.
interface IERC5192 {
    event Locked(uint256 tokenId);
    event Unlocked(uint256 tokenId);
    function locked(uint256 tokenId) external view returns (bool);
}

/// @title Dojo Pass DNA
/// @notice A living, soulbound edition of the Dojo Pass, fully on-chain. Modelled on
/// Zerion DNA (0x9322…848bf), but instead of pointing at an off-chain metadata
/// server, tokenURI reads live state (days since mint, registry Practitioner flag,
/// HONOR trades, standing and virtues) and renders JSON + SVG on-chain at read time.
/// The pass evolves the moment its holder's on-chain record does: no backend, no
/// metadata writes, no per-update gas.
///
///  - Mint is gated on the live Dojo Pass registry (earned, never bought here; no fee).
///  - tokenId = uint160(holder): one pass per wallet.
///  - Soulbound (ERC-5192): no transfers or approvals. Holder may burn; owner may burn
///    only when the registry pass has been revoked.
///  - The renderer is a separate contract the owner can replace (art upgrades), and
///    ERC-4906 events tell marketplaces to re-fetch.
contract DojoPassDNA is ERC721, Ownable, Pausable, IERC5192 {
    /// @notice The live Dojo Pass registry on this chain.
    IDojoPass public immutable dojoPass;
    /// @notice HONOR on this chain, or zero where there is none (e.g. Base).
    IHonor public honor;
    IDojoPassRenderer public renderer;

    /// @notice Collection-level metadata (OpenSea convention).
    string public contractURI;
    uint256 public totalSupply;
    mapping(uint256 => uint256) public mintedAt;

    // ERC-4906
    event MetadataUpdate(uint256 tokenId);
    event BatchMetadataUpdate(uint256 fromTokenId, uint256 toTokenId);

    error NoDojoPass();
    error Soulbound();
    error PassStillActive();
    error NotHolder();
    error ZeroAddress();

    constructor(IDojoPass registry, IHonor honor_, IDojoPassRenderer renderer_, address owner_, string memory contractURI_)
        ERC721("Dojo Pass DNA", "DOJODNA")
    {
        if (address(registry) == address(0) || address(renderer_) == address(0) || owner_ == address(0)) {
            revert ZeroAddress();
        }
        dojoPass = registry;
        honor = honor_;
        renderer = renderer_;
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
        mintedAt[tokenId] = block.timestamp;
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
        delete mintedAt[tokenId];
        unchecked {
            --totalSupply;
        }
    }

    // ------------------------------------------------------------------ living metadata

    /// @notice Fully on-chain metadata, recomputed from live state on every read.
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        return renderer.tokenURI(passState(tokenId));
    }

    /// @notice The live state tokenURI renders. Never reverts on a misbehaving HONOR:
    /// unreadable feeds render as "Not yet recorded".
    function passState(uint256 tokenId) public view returns (PassState memory p) {
        address holder = ownerOf(tokenId);
        p.tokenId = tokenId;
        p.holder = holder;
        p.chainId = block.chainid;
        p.ageDays = (block.timestamp - mintedAt[tokenId]) / 1 days;
        try dojoPass.isPractitioner(holder) returns (bool ok) {
            p.practitioner = ok;
        } catch {}
        _readHonor(p);
    }

    function _readHonor(PassState memory p) private view {
        IHonor h = honor;
        if (address(h) == address(0)) return;
        try h.tradeCount(p.holder) returns (uint256 t) {
            try h.honorScores(p.holder) returns (uint256 s) {
                try h.getVirtueScores(p.holder) returns (uint256 gi, uint256 yu, uint256 jin, uint256 rei, uint256 makoto) {
                    p.trades = t;
                    p.standing = s > 100 ? 100 : s;
                    p.virtues = [_cap(gi), _cap(yu), _cap(jin), _cap(rei), _cap(makoto)];
                    p.honorWired = true;
                } catch {}
            } catch {}
        } catch {}
    }

    function _cap(uint256 score) private pure returns (uint8) {
        return uint8(score > 10 ? 10 : score);
    }

    /// @notice Anyone may ask marketplaces to re-fetch a pass after its record changed.
    /// Only emits an event; metadata itself is always live.
    function refreshMetadata(uint256 tokenId) external {
        ownerOf(tokenId); // must exist
        emit MetadataUpdate(tokenId);
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

    /// @notice Swap the on-chain art. Every pass re-renders.
    function setRenderer(IDojoPassRenderer newRenderer) external onlyOwner {
        if (address(newRenderer) == address(0)) revert ZeroAddress();
        renderer = newRenderer;
        emit BatchMetadataUpdate(0, type(uint256).max);
    }

    /// @notice Point at HONOR (or zero to disable the feed). Every pass re-renders.
    function setHonor(IHonor newHonor) external onlyOwner {
        honor = newHonor;
        emit BatchMetadataUpdate(0, type(uint256).max);
    }

    function setContractURI(string calldata newContractURI) external onlyOwner {
        contractURI = newContractURI;
    }

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
