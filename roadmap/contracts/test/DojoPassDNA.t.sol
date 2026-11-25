// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {DojoPassDNA, IDojoPass} from "../src/DojoPassDNA.sol";
import {TestDojoPass} from "../src/testnet/TestDojoPass.sol";
import {vm} from "./mocks/Vm.sol";

contract Receiver {
    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }
}

contract DojoPassDNATest {
    address constant OWNER = address(0xB051D0);
    address constant ALICE = address(0xA11CE);
    address constant BOB = address(0xB0B);
    address constant STRANGER = address(0xBAD);
    string constant BASE = "https://example.test/api/dojo-pass/base/token/";

    TestDojoPass registry;
    DojoPassDNA dna;

    function setUp() public {
        vm.warp(1_800_000_000);
        registry = new TestDojoPass(OWNER, 0.001 ether);
        dna = new DojoPassDNA(IDojoPass(address(registry)), OWNER, BASE, "https://example.test/contract.json");
        vm.startPrank(OWNER);
        registry.grantPass(ALICE);
        dna.unpause();
        vm.stopPrank();
    }

    // ---------------------------------------------------------------- helpers
    function _eq(uint256 a, uint256 b, string memory m) internal pure {
        require(a == b, m);
    }

    function _err(string memory reason) internal pure returns (bytes memory) {
        return abi.encodeWithSignature("Error(string)", reason);
    }

    function _mintAs(address who) internal returns (uint256 id) {
        vm.prank(who);
        id = dna.mint();
    }

    // ---------------------------------------------------------------- deploy
    function test_startsPausedLikeZerion() public {
        DojoPassDNA fresh = new DojoPassDNA(IDojoPass(address(registry)), OWNER, BASE, "");
        require(fresh.paused(), "should start paused");
        require(fresh.owner() == OWNER, "owner");
        vm.prank(ALICE);
        vm.expectRevert(_err("Pausable: paused"));
        fresh.mint();
    }

    function test_constructorRejectsZeroAddresses() public {
        vm.expectRevert(DojoPassDNA.ZeroAddress.selector);
        new DojoPassDNA(IDojoPass(address(0)), OWNER, BASE, "");
        vm.expectRevert(DojoPassDNA.ZeroAddress.selector);
        new DojoPassDNA(IDojoPass(address(registry)), address(0), BASE, "");
    }

    // ---------------------------------------------------------------- mint gate
    function test_mintRequiresDojoPass() public {
        vm.prank(BOB);
        vm.expectRevert(DojoPassDNA.NoDojoPass.selector);
        dna.mint();
    }

    function test_mintTokenIdIsHolderAddress() public {
        uint256 id = _mintAs(ALICE);
        _eq(id, uint256(uint160(ALICE)), "tokenId = uint160(holder)");
        _eq(id, dna.tokenIdOf(ALICE), "tokenIdOf");
        require(dna.ownerOf(id) == ALICE, "ownerOf");
        _eq(dna.totalSupply(), 1, "supply");
        _eq(dna.balanceOf(ALICE), 1, "balance");
        require(dna.locked(id), "locked");
    }

    function test_onePerWallet() public {
        _mintAs(ALICE);
        vm.prank(ALICE);
        vm.expectRevert(_err("ERC721: token already minted"));
        dna.mint();
    }

    function test_purchasedPassCanMint() public {
        vm.deal(BOB, 1 ether);
        vm.prank(BOB);
        registry.purchasePass{value: 0.001 ether}();
        _mintAs(BOB);
        _eq(dna.totalSupply(), 1, "supply");
    }

    function test_contractWalletCanMint() public {
        Receiver r = new Receiver();
        vm.prank(OWNER);
        registry.grantPass(address(r));
        _mintAs(address(r));
        require(dna.ownerOf(dna.tokenIdOf(address(r))) == address(r), "contract holder");
    }

    // ---------------------------------------------------------------- soulbound
    function test_transfersRevert() public {
        uint256 id = _mintAs(ALICE);
        vm.startPrank(ALICE);
        vm.expectRevert(DojoPassDNA.Soulbound.selector);
        dna.transferFrom(ALICE, BOB, id);
        vm.expectRevert(DojoPassDNA.Soulbound.selector);
        dna.safeTransferFrom(ALICE, BOB, id);
        vm.expectRevert(DojoPassDNA.Soulbound.selector);
        dna.safeTransferFrom(ALICE, BOB, id, "");
        vm.stopPrank();
        require(dna.ownerOf(id) == ALICE, "still Alice's");
    }

    function test_approvalsRevert() public {
        uint256 id = _mintAs(ALICE);
        vm.startPrank(ALICE);
        vm.expectRevert(DojoPassDNA.Soulbound.selector);
        dna.approve(BOB, id);
        vm.expectRevert(DojoPassDNA.Soulbound.selector);
        dna.setApprovalForAll(BOB, true);
        vm.stopPrank();
    }

    function test_lockedRevertsForUnminted() public {
        vm.expectRevert(_err("ERC721: invalid token ID"));
        dna.locked(123);
    }

    // ---------------------------------------------------------------- burn
    function test_holderBurnsOwnPass() public {
        _mintAs(ALICE);
        vm.prank(ALICE);
        dna.burn();
        _eq(dna.totalSupply(), 0, "supply");
        _eq(dna.balanceOf(ALICE), 0, "balance");
        // and can re-mint while the registry pass is still active
        _mintAs(ALICE);
        _eq(dna.totalSupply(), 1, "re-minted");
    }

    function test_burnWithoutTokenReverts() public {
        vm.prank(BOB);
        vm.expectRevert(DojoPassDNA.NotHolder.selector);
        dna.burn();
    }

    function test_ownerBurnsOnlyRevokedPasses() public {
        _mintAs(ALICE);
        vm.prank(OWNER);
        vm.expectRevert(DojoPassDNA.PassStillActive.selector);
        dna.burnRevoked(ALICE);

        vm.prank(OWNER);
        registry.revokePass(ALICE);
        vm.prank(STRANGER);
        vm.expectRevert(_err("Ownable: caller is not the owner"));
        dna.burnRevoked(ALICE);

        vm.prank(OWNER);
        dna.burnRevoked(ALICE);
        _eq(dna.totalSupply(), 0, "burned");

        // revoked holder cannot mint again
        vm.prank(ALICE);
        vm.expectRevert(DojoPassDNA.NoDojoPass.selector);
        dna.mint();
    }

    function test_burnRevokedWithoutTokenReverts() public {
        vm.prank(OWNER);
        vm.expectRevert(DojoPassDNA.NotHolder.selector);
        dna.burnRevoked(BOB); // BOB has no registry pass and no token
    }

    // ---------------------------------------------------------------- metadata
    function test_tokenURIIsBasePlusDecimalId() public {
        uint256 id = _mintAs(ALICE);
        bytes memory expected = abi.encodePacked(BASE, _toString(id));
        require(keccak256(bytes(dna.tokenURI(id))) == keccak256(expected), "tokenURI");
    }

    function test_onlyOwnerSetsURIs() public {
        vm.startPrank(STRANGER);
        vm.expectRevert(_err("Ownable: caller is not the owner"));
        dna.setBaseURI("x");
        vm.expectRevert(_err("Ownable: caller is not the owner"));
        dna.setContractURI("x");
        vm.stopPrank();

        uint256 id = _mintAs(ALICE);
        vm.startPrank(OWNER);
        dna.setBaseURI("ipfs://new/");
        dna.setContractURI("ipfs://c");
        vm.stopPrank();
        require(keccak256(bytes(dna.tokenURI(id))) == keccak256(abi.encodePacked("ipfs://new/", _toString(id))), "new base");
        require(keccak256(bytes(dna.contractURI())) == keccak256("ipfs://c"), "contractURI");
    }

    function test_refreshMetadataHolderOrOwnerOnly() public {
        uint256 id = _mintAs(ALICE);
        vm.prank(ALICE);
        dna.refreshMetadata(id);
        vm.prank(OWNER);
        dna.refreshMetadata(id);
        vm.prank(STRANGER);
        vm.expectRevert(DojoPassDNA.NotHolder.selector);
        dna.refreshMetadata(id);
    }

    function test_pauseIsOwnerOnly() public {
        vm.prank(STRANGER);
        vm.expectRevert(_err("Ownable: caller is not the owner"));
        dna.pause();
        vm.prank(OWNER);
        dna.pause();
        vm.prank(ALICE);
        vm.expectRevert(_err("Pausable: paused"));
        dna.mint();
    }

    function test_supportsInterfaces() public view {
        require(dna.supportsInterface(0x80ac58cd), "ERC721");
        require(dna.supportsInterface(0x5b5e139f), "ERC721Metadata");
        require(dna.supportsInterface(0xb45a3c0e), "ERC5192");
        require(dna.supportsInterface(0x49064906), "ERC4906");
        require(dna.supportsInterface(0x01ffc9a7), "ERC165");
        require(!dna.supportsInterface(0xffffffff), "invalid id");
    }

    // ---------------------------------------------------------------- fuzz
    function testFuzz_anyPassHolderMintsOwnId(address who) public {
        vm.assume(who != address(0) && who.code.length == 0 && who != ALICE);
        vm.prank(OWNER);
        registry.grantPass(who);
        uint256 id = _mintAs(who);
        _eq(id, uint256(uint160(who)), "id");
        require(dna.ownerOf(id) == who, "owner");
    }

    function _toString(uint256 v) internal pure returns (string memory) {
        if (v == 0) return "0";
        uint256 len;
        for (uint256 t = v; t != 0; t /= 10) len++;
        bytes memory b = new bytes(len);
        while (v != 0) {
            b[--len] = bytes1(uint8(48 + (v % 10)));
            v /= 10;
        }
        return string(b);
    }
}
