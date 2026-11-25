// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {DojoPassDNA} from "../src/dna/DojoPassDNA.sol";
import {IDojoPassDNA, IDojoPass} from "../src/dna/IDojoPassDNA.sol";
import {TestDojoPass} from "../src/testnet/TestDojoPass.sol";
import {vm} from "./mocks/Vm.sol";

contract NoReceiver {}

contract DojoPassDNATest {
    address constant OWNER = address(0xB051D0);
    address constant ALICE = address(0xA11CE);
    address constant BOB = address(0xB0B);
    address constant STRANGER = address(0xBAD);
    uint256 constant PRICE = 0.0001 ether;

    TestDojoPass registry;
    DojoPassDNA dna;

    function setUp() public {
        registry = new TestDojoPass(OWNER, 0.001 ether, ALICE);
        vm.prank(OWNER);
        dna = new DojoPassDNA(IDojoPass(address(registry)));
        vm.prank(OWNER);
        dna.unpause();
        vm.deal(ALICE, 1 ether);
        vm.deal(BOB, 1 ether);
    }

    function _eq(uint256 a, uint256 b, string memory m) internal pure {
        require(a == b, m);
    }

    function _err(string memory reason) internal pure returns (bytes memory) {
        return abi.encodeWithSignature("Error(string)", reason);
    }

    function _same(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(bytes(a)) == keccak256(bytes(b));
    }

    function _mintAs(address who) internal returns (uint256) {
        vm.prank(who);
        dna.mint{value: PRICE}();
        return dna.tokenIdOf(who);
    }

    // ------------------------------------------------------------ deploy (Zerion template)
    function test_deploysPausedOwnedByDeployer() public {
        vm.prank(OWNER);
        DojoPassDNA fresh = new DojoPassDNA(IDojoPass(address(registry)));
        require(fresh.paused() && fresh.owner() == OWNER, "paused + owner");
        require(_same(fresh.name(), "Dojo Pass DNA") && _same(fresh.symbol(), "DOJODNA"), "name");
        _eq(fresh.mintPrice(), PRICE, "0.0001 ether");
        require(address(fresh.dojoPass()) == address(registry), "registry");
        vm.prank(ALICE);
        vm.expectRevert(_err("Pausable: paused"));
        fresh.mint{value: PRICE}();
        vm.expectRevert(IDojoPassDNA.ZeroAddress.selector);
        new DojoPassDNA(IDojoPass(address(0)));
    }

    // ------------------------------------------------------------ mint
    function test_mintGatedOnDojoPass() public {
        vm.prank(BOB);
        vm.expectRevert(IDojoPassDNA.NoDojoPass.selector);
        dna.mint{value: PRICE}();
    }

    function test_mintRequiresExactPrice() public {
        vm.startPrank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(IDojoPassDNA.WrongMintPrice.selector, 0, PRICE));
        dna.mint();
        vm.expectRevert(abi.encodeWithSelector(IDojoPassDNA.WrongMintPrice.selector, PRICE + 1, PRICE));
        dna.mint{value: PRICE + 1}();
        vm.stopPrank();
    }

    function test_tokenIdIsHolderAndOnePerWallet() public {
        uint256 id = _mintAs(ALICE);
        _eq(id, uint256(uint160(ALICE)), "tokenId = uint160(holder)");
        require(dna.ownerOf(id) == ALICE && dna.locked(id), "owned + locked");
        _eq(dna.totalSupply(), 1, "supply");
        _eq(address(dna).balance, PRICE, "fee held");
        vm.prank(ALICE);
        vm.expectRevert(_err("ERC721: token already minted"));
        dna.mint{value: PRICE}();
    }

    function test_purchasedPassCanMint() public {
        vm.prank(BOB);
        registry.purchasePass{value: 0.001 ether}();
        _mintAs(BOB);
        _eq(dna.totalSupply(), 1, "bob minted");
    }

    function test_contractWithoutReceiverCanMint() public {
        // plain _mint: a soulbound token never moves, so no onERC721Received callback (7702 burners)
        address n = address(new NoReceiver());
        vm.deal(n, 1 ether);
        vm.prank(OWNER);
        registry.grantPass(n);
        _mintAs(n);
        require(dna.ownerOf(dna.tokenIdOf(n)) == n, "minted");
    }

    function test_ownerCanRepriceIncludingFree() public {
        vm.prank(STRANGER);
        vm.expectRevert(_err("Ownable: caller is not the owner"));
        dna.setMintPrice(0);
        vm.prank(OWNER);
        dna.setMintPrice(0);
        vm.prank(ALICE);
        dna.mint();
        _eq(dna.totalSupply(), 1, "free mint");
    }

    // ------------------------------------------------------------ soulbound
    function test_transfersAndApprovalsRevert() public {
        uint256 id = _mintAs(ALICE);
        vm.startPrank(ALICE);
        vm.expectRevert(IDojoPassDNA.Soulbound.selector);
        dna.transferFrom(ALICE, BOB, id);
        vm.expectRevert(IDojoPassDNA.Soulbound.selector);
        dna.safeTransferFrom(ALICE, BOB, id);
        vm.expectRevert(IDojoPassDNA.Soulbound.selector);
        dna.safeTransferFrom(ALICE, BOB, id, "");
        vm.expectRevert(IDojoPassDNA.Soulbound.selector);
        dna.approve(BOB, id);
        vm.expectRevert(IDojoPassDNA.Soulbound.selector);
        dna.setApprovalForAll(BOB, true);
        vm.stopPrank();
        require(dna.ownerOf(id) == ALICE, "still Alice's");
    }

    function test_lockedRevertsForUnminted() public {
        vm.expectRevert(_err("ERC721: invalid token ID"));
        dna.locked(123);
    }

    // ------------------------------------------------------------ burn
    function test_holderBurnsAndCanRemint() public {
        _mintAs(ALICE);
        vm.prank(ALICE);
        dna.burn();
        _eq(dna.totalSupply(), 0, "burned");
        _mintAs(ALICE);
        _eq(dna.totalSupply(), 1, "re-minted");
        vm.prank(BOB);
        vm.expectRevert(IDojoPassDNA.NotHolder.selector);
        dna.burn();
    }

    function test_ownerBurnsOnlyRevokedPasses() public {
        _mintAs(ALICE);
        vm.prank(OWNER);
        vm.expectRevert(IDojoPassDNA.PassStillActive.selector);
        dna.burnRevoked(ALICE);
        vm.prank(OWNER);
        registry.revokePass(ALICE);
        vm.prank(STRANGER);
        vm.expectRevert(_err("Ownable: caller is not the owner"));
        dna.burnRevoked(ALICE);
        vm.prank(OWNER);
        dna.burnRevoked(ALICE);
        _eq(dna.totalSupply(), 0, "burned");
        vm.prank(OWNER);
        vm.expectRevert(IDojoPassDNA.NotHolder.selector);
        dna.burnRevoked(BOB);
        vm.prank(ALICE);
        vm.expectRevert(IDojoPassDNA.NoDojoPass.selector);
        dna.mint{value: PRICE}();
    }

    // ------------------------------------------------------------ traits (Zerion model)
    function test_tokenURIIsBasePlusHolderId() public {
        uint256 id = _mintAs(ALICE);
        require(_same(dna.tokenURI(id), ""), "empty until base set");
        vm.prank(OWNER);
        dna.setBaseURI("https://example.test/api/dojo-pass/base-sepolia/");
        require(
            _same(dna.tokenURI(id), "https://example.test/api/dojo-pass/base-sepolia/659918"),
            "base + decimal uint160(holder)"
        );
    }

    function test_onlyOwnerSetsURIs() public {
        vm.startPrank(STRANGER);
        vm.expectRevert(_err("Ownable: caller is not the owner"));
        dna.setBaseURI("x");
        vm.expectRevert(_err("Ownable: caller is not the owner"));
        dna.setContractURI("x");
        vm.stopPrank();
        vm.prank(OWNER);
        dna.setContractURI("ipfs://collection");
        require(_same(dna.contractURI(), "ipfs://collection"), "contractURI");
    }

    function test_refreshMetadataHolderOrOwnerOnly() public {
        uint256 id = _mintAs(ALICE);
        vm.prank(ALICE);
        dna.refreshMetadata(id);
        vm.prank(OWNER);
        dna.refreshMetadata(id);
        vm.prank(STRANGER);
        vm.expectRevert(IDojoPassDNA.NotHolder.selector);
        dna.refreshMetadata(id);
    }

    // ------------------------------------------------------------ fees + admin
    function test_withdrawSendsFeesToOwner() public {
        _mintAs(ALICE);
        vm.prank(STRANGER);
        vm.expectRevert(_err("Ownable: caller is not the owner"));
        dna.withdraw();
        uint256 before = OWNER.balance;
        vm.prank(OWNER);
        dna.withdraw();
        _eq(OWNER.balance - before, PRICE, "owner paid");
        _eq(address(dna).balance, 0, "emptied");
    }

    function test_withdrawToRejectingOwnerReverts() public {
        _mintAs(ALICE);
        NoReceiver n = new NoReceiver();
        vm.prank(OWNER);
        dna.transferOwnership(address(n));
        vm.prank(address(n));
        vm.expectRevert(IDojoPassDNA.WithdrawFailed.selector);
        dna.withdraw();
    }

    function test_pauseIsOwnerOnly() public {
        vm.prank(STRANGER);
        vm.expectRevert(_err("Ownable: caller is not the owner"));
        dna.pause();
        vm.prank(OWNER);
        dna.pause();
        vm.prank(ALICE);
        vm.expectRevert(_err("Pausable: paused"));
        dna.mint{value: PRICE}();
    }

    function test_supportsInterfaces() public view {
        require(dna.supportsInterface(0x80ac58cd), "ERC721");
        require(dna.supportsInterface(0x5b5e139f), "ERC721Metadata");
        require(dna.supportsInterface(0x01ffc9a7), "ERC165");
        require(dna.supportsInterface(0xe8a3d485), "IContractURI");
        require(dna.supportsInterface(0xb45a3c0e), "ERC5192");
        require(dna.supportsInterface(0x49064906), "ERC4906");
        require(!dna.supportsInterface(0xffffffff), "invalid");
    }

    function testFuzz_anyPassHolderMintsOwnId(address who) public {
        vm.assume(who != address(0) && who != ALICE && uint160(who) > 0xff && who.code.length == 0);
        vm.prank(OWNER);
        registry.grantPass(who);
        vm.deal(who, 1 ether);
        uint256 id = _mintAs(who);
        _eq(id, uint256(uint160(who)), "id");
        require(dna.ownerOf(id) == who, "owner");
    }
}
