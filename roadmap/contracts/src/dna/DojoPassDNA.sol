// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

import "./IContractURI.sol";
import "./IDojoPassDNA.sol";

/// @title Dojo Pass DNA
/// @notice A clone of Zerion DNA 1.0 (Ethereum 0x932261f9fc8da46c4a22e31b45c4de60623848bf): a plain
/// ERC-721 whose metadata lives behind an owner-set base URI and is recomputed off-chain, so the
/// pass evolves with its holder. Deviations from Zerion's source, and nothing else:
///  - mint costs `mintPrice` (0.0001 ether at deploy, owner-settable); fees are withdrawn to the owner.
///  - no OpenSea proxy-registry auto-approval: that registry (0xa540…77c1) has no code on Base,
///    Monad or their testnets (checked 2026-11-25), so calling it would revert every isApprovedForAll.
///  - name/symbol are Dojo Pass DNA / DOJODNA.
contract DojoPassDNA is Ownable, Pausable, ERC721, IContractURI, IDojoPassDNA {
    /// @inheritdoc IContractURI
    string public override contractURI;

    /// @inheritdoc IDojoPassDNA
    uint256 public override totalSupply;

    /// @inheritdoc IDojoPassDNA
    uint256 public override mintPrice = 0.0001 ether;

    // Prefix of each tokenURI
    string internal baseURI;

    /// @notice Creates Dojo Pass DNA (paused, like Zerion DNA)
    constructor() ERC721("Dojo Pass DNA", "DOJODNA") {
        _pause();
    }

    /// @inheritdoc IDojoPassDNA
    function setBaseURI(string memory newBaseURI) external override onlyOwner {
        baseURI = newBaseURI;
    }

    /// @inheritdoc IDojoPassDNA
    function setContractURI(string memory newContractURI) external override onlyOwner {
        contractURI = newContractURI;
    }

    /// @inheritdoc IDojoPassDNA
    function mint() external payable override whenNotPaused {
        if (msg.value != mintPrice) revert WrongMintPrice(msg.value, mintPrice);
        _safeMint(_msgSender(), totalSupply++);
    }

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
        return interfaceId == type(IContractURI).interfaceId || super.supportsInterface(interfaceId);
    }

    /// @inheritdoc ERC721
    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }
}
