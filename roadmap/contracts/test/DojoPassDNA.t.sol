// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {DojoPassDNA, IDojoPass, IHonor} from "../src/DojoPassDNA.sol";
import {DojoPassRenderer, PassState} from "../src/DojoPassRenderer.sol";
import {TestHonor} from "../src/testnet/TestHonor.sol";
import {DojoPassDNATestnetKit} from "../src/testnet/DojoPassDNATestnetKit.sol";
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

    TestDojoPass registry;
    TestHonor honor;
    DojoPassRenderer renderer;
    DojoPassDNA dna;

    function setUp() public {
        vm.warp(1_800_000_000);
        registry = new TestDojoPass(OWNER, 0.001 ether, address(0));
        honor = new TestHonor(OWNER);
        renderer = new DojoPassRenderer();
        dna = _newDna(IHonor(address(honor)));
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

    function _newDna(IHonor h) internal returns (DojoPassDNA) {
        return new DojoPassDNA(IDojoPass(address(registry)), h, renderer, OWNER, "https://example.test/contract.json");
    }

    function _mintAs(address who) internal returns (uint256 id) {
        vm.prank(who);
        id = dna.mint();
    }

    // ---------------------------------------------------------------- deploy
    function test_startsPausedLikeZerion() public {
        DojoPassDNA fresh = _newDna(IHonor(address(honor)));
        require(fresh.paused(), "should start paused");
        require(fresh.owner() == OWNER, "owner");
        vm.prank(ALICE);
        vm.expectRevert(_err("Pausable: paused"));
        fresh.mint();
    }

    function test_constructorRejectsZeroAddresses() public {
        vm.expectRevert(DojoPassDNA.ZeroAddress.selector);
        new DojoPassDNA(IDojoPass(address(0)), IHonor(address(honor)), renderer, OWNER, "");
        vm.expectRevert(DojoPassDNA.ZeroAddress.selector);
        new DojoPassDNA(IDojoPass(address(registry)), IHonor(address(honor)), DojoPassRenderer(address(0)), OWNER, "");
        vm.expectRevert(DojoPassDNA.ZeroAddress.selector);
        new DojoPassDNA(IDojoPass(address(registry)), IHonor(address(honor)), renderer, address(0), "");
        // HONOR may be zero (chains without it, e.g. Base)
        new DojoPassDNA(IDojoPass(address(registry)), IHonor(address(0)), renderer, OWNER, "");
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

    // ---------------------------------------------------------------- living, on-chain metadata
    function _contains(string memory hay, string memory needle) internal pure returns (bool) {
        bytes memory h = bytes(hay);
        bytes memory n = bytes(needle);
        if (n.length > h.length) return false;
        for (uint256 i; i <= h.length - n.length; ++i) {
            bool ok = true;
            for (uint256 j; j < n.length && ok; ++j) ok = h[i + j] == n[j];
            if (ok) return true;
        }
        return false;
    }

    function _json(uint256 id) internal view returns (string memory) {
        return renderer.json(dna.passState(id));
    }

    function _svg(uint256 id) internal view returns (string memory) {
        return renderer.svg(dna.passState(id));
    }

    function _record(address who, uint256 standing, uint8[5] memory v) internal {
        vm.prank(OWNER);
        honor.record(who, standing, v);
    }

    function test_tokenURIIsOnChainJson() public {
        uint256 id = _mintAs(ALICE);
        string memory uri = dna.tokenURI(id);
        require(_contains(uri, "data:application/json;base64,"), "data URI");
        string memory j = _json(id);
        require(_contains(j, '"image":"data:image/svg+xml;base64,'), "inline SVG image");
        require(_contains(j, '{"trait_type":"Rank","value":"Tsurano"}'), "fresh pass is Tsurano");
        require(_contains(j, '{"trait_type":"Recorded Trades","value":0,"display_type":"number"}'), "0 trades");
        require(_contains(j, '{"trait_type":"Practitioner","value":"Yes"}'), "practitioner");
        require(_contains(j, unicode'{"trait_type":"Virtue — Gi","value":0,"display_type":"number","max_value":4}'), "Gi 0");
        require(_contains(j, unicode'{"trait_type":"Virtue — Jisei","value":"Not yet recorded"}'), "Jisei gap");
        require(_contains(j, '{"trait_type":"Check-in Streak (days)","value":"Not yet recorded"}'), "streak gap");
    }

    function test_passEvolvesWithRecordedTrades() public {
        uint256 id = _mintAs(ALICE);
        string memory before = dna.tokenURI(id);

        _record(ALICE, 66, [uint8(5), 3, 10, 0, 8]);
        string memory j = _json(id);
        require(keccak256(bytes(before)) != keccak256(bytes(dna.tokenURI(id))), "tokenURI changed");
        require(_contains(j, '{"trait_type":"Rank","value":"Samurai"}'), "Samurai");
        require(_contains(j, '{"trait_type":"Recorded Trades","value":1,"display_type":"number"}'), "1 trade");
        require(_contains(j, unicode'{"trait_type":"Virtue — Gi","value":2,'), "Gi 5 -> tier 2");
        require(_contains(j, unicode'{"trait_type":"Virtue — Jin","value":4,'), "Jin 10 -> tier 4");
        require(_contains(j, unicode'{"trait_type":"Virtue — Makoto","value":4,'), "Makoto 8 -> tier 4");
        require(_contains(_svg(id), '#4A4F57'), "iron frame");

        _record(ALICE, 95, [uint8(10), 10, 10, 10, 10]);
        require(_contains(_json(id), '{"trait_type":"Rank","value":"Shogun"}'), "Shogun");
        require(_contains(_svg(id), '#D4AF37" stroke-width="20"') || _contains(_svg(id), '#0B0B0B'), "black-gold frame");
    }

    function test_passAgeCountsDaysSinceMint() public {
        uint256 id = _mintAs(ALICE);
        vm.warp(block.timestamp + 10 days + 1 hours);
        _eq(dna.passState(id).ageDays, 10, "10 days");
    }

    function test_standingAndScoresAreClamped() public {
        uint256 id = _mintAs(ALICE);
        _record(ALICE, 500, [uint8(10), 10, 10, 10, 10]);
        PassState memory p = dna.passState(id);
        _eq(p.standing, 100, "standing clamps to 100");
    }

    function test_brokenHonorRendersGapsNotRevert() public {
        dna = _newDna(IHonor(address(new Reverter())));
        vm.prank(OWNER);
        dna.unpause();
        uint256 id = _mintAs(ALICE);
        string memory j = _json(id);
        require(_contains(j, '{"trait_type":"Recorded Trades","value":"Not yet recorded"}'), "trades gap");
        require(_contains(j, unicode'{"trait_type":"Virtue — Gi","value":"Not yet recorded"}'), "Gi gap");
        require(bytes(dna.tokenURI(id)).length > 0, "still renders");
    }

    function test_noHonorChain() public {
        dna = _newDna(IHonor(address(0)));
        vm.prank(OWNER);
        dna.unpause();
        uint256 id = _mintAs(ALICE);
        require(!dna.passState(id).honorWired, "not wired");
        require(_contains(_json(id), "trades and virtues on this chain"), "explains gap");
    }

    function test_tokenURIRevertsForUnminted() public {
        vm.expectRevert(_err("ERC721: invalid token ID"));
        dna.tokenURI(42);
    }

    function test_rendererAndHonorSwapsAreOwnerOnly() public {
        DojoPassRenderer r2 = new DojoPassRenderer();
        vm.startPrank(STRANGER);
        vm.expectRevert(_err("Ownable: caller is not the owner"));
        dna.setRenderer(r2);
        vm.expectRevert(_err("Ownable: caller is not the owner"));
        dna.setHonor(IHonor(address(0)));
        vm.expectRevert(_err("Ownable: caller is not the owner"));
        dna.setContractURI("x");
        vm.stopPrank();

        vm.startPrank(OWNER);
        vm.expectRevert(DojoPassDNA.ZeroAddress.selector);
        dna.setRenderer(DojoPassRenderer(address(0)));
        dna.setRenderer(r2);
        dna.setHonor(IHonor(address(0)));
        dna.setContractURI("ipfs://c");
        vm.stopPrank();
        require(address(dna.renderer()) == address(r2), "renderer");
        require(address(dna.honor()) == address(0), "honor off");
    }

    function test_refreshMetadataNeedsExistingToken() public {
        uint256 id = _mintAs(ALICE);
        vm.prank(STRANGER);
        dna.refreshMetadata(id);
        vm.expectRevert(_err("ERC721: invalid token ID"));
        dna.refreshMetadata(7);
    }

    function test_rendererTiers() public view {
        _eq(renderer.tier(0), 0, "0");
        _eq(renderer.tier(1), 1, "1");
        _eq(renderer.tier(3), 2, "3");
        _eq(renderer.tier(5), 2, "5");
        _eq(renderer.tier(6), 3, "6");
        _eq(renderer.tier(8), 4, "8");
        _eq(renderer.tier(10), 4, "10");
    }

    function test_rendererRankBands() public view {
        require(keccak256(bytes(renderer.rank(59))) == keccak256("Tsurano"), "59");
        require(keccak256(bytes(renderer.rank(60))) == keccak256("Samurai"), "60");
        require(keccak256(bytes(renderer.rank(74))) == keccak256("Samurai"), "74");
        require(keccak256(bytes(renderer.rank(75))) == keccak256("Bushido Master"), "75");
        require(keccak256(bytes(renderer.rank(89))) == keccak256("Bushido Master"), "89");
        require(keccak256(bytes(renderer.rank(90))) == keccak256("Shogun"), "90");
    }

    function test_honorRejectsOutOfRangeScore() public {
        vm.prank(OWNER);
        vm.expectRevert(TestHonor.InvalidVirtueScore.selector);
        honor.record(ALICE, 1, [uint8(11), 0, 0, 0, 0]);
        vm.prank(STRANGER);
        vm.expectRevert(TestHonor.NotOwner.selector);
        honor.record(ALICE, 1, [uint8(1), 0, 0, 0, 0]);
    }

    // ---------------------------------------------------------------- testnet kit (burner page)
    function test_kitWiresEverythingForBurner() public {
        DojoPassDNATestnetKit kit = new DojoPassDNATestnetKit(BOB);
        DojoPassDNA d = kit.dna();
        require(d.owner() == BOB, "DNA owned by burner");
        require(!d.paused(), "minting open");
        require(kit.registry().hasDojoPass(BOB), "burner has a pass");
        require(kit.registry().owner() == BOB, "registry owned by burner");
        require(kit.honor().owner() == BOB, "honor owned by burner");
        require(address(d.honor()) == address(kit.honor()), "honor wired");
        vm.prank(BOB);
        uint256 id = d.mint();
        vm.prank(BOB);
        kit.honor().record(BOB, 81, [uint8(8), 8, 8, 8, 8]);
        require(_contains(kit.renderer().json(d.passState(id)), '{"trait_type":"Rank","value":"Bushido Master"}'), "evolves");
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

/// @dev HONOR that reverts on every read.
contract Reverter {
    fallback() external {
        revert("broken");
    }
}
