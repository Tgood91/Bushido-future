// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {DojoPassDNA} from "../src/dna/DojoPassDNA.sol";
import {IDojoPassDNA} from "../src/dna/IDojoPassDNA.sol";
import {vm} from "./mocks/Vm.sol";

contract Receiver {
    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }
}

contract NoReceiver {}

contract DojoPassDNATest {
    address constant OWNER = address(0xB051D0);
    address constant ALICE = address(0xA11CE);
    address constant BOB = address(0xB0B);
    address constant STRANGER = address(0xBAD);
    uint256 constant PRICE = 0.0001 ether;

    DojoPassDNA dna;

    receive() external payable {}

    function setUp() public {
        vm.prank(OWNER);
        dna = new DojoPassDNA();
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

    function _mintAs(address who) internal returns (uint256 id) {
        id = dna.totalSupply();
        vm.prank(who);
        dna.mint{value: PRICE}();
    }

    function _same(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(bytes(a)) == keccak256(bytes(b));
    }

    // ------------------------------------------------------------ deploy (as Zerion DNA)
    function test_deploysPausedOwnedByDeployer() public {
        vm.prank(OWNER);
        DojoPassDNA fresh = new DojoPassDNA();
        require(fresh.paused(), "paused");
        require(fresh.owner() == OWNER, "owner");
        require(_same(fresh.name(), "Dojo Pass DNA") && _same(fresh.symbol(), "DOJODNA"), "name");
        _eq(fresh.mintPrice(), PRICE, "0.0001 ether");
        vm.prank(ALICE);
        vm.expectRevert(_err("Pausable: paused"));
        fresh.mint{value: PRICE}();
    }

    // ------------------------------------------------------------ mint
    function test_mintSequentialIds() public {
        _eq(_mintAs(ALICE), 0, "first id 0");
        _eq(_mintAs(BOB), 1, "second id 1");
        _eq(_mintAs(ALICE), 2, "wallets may mint again, like Zerion");
        _eq(dna.totalSupply(), 3, "supply");
        _eq(dna.balanceOf(ALICE), 2, "alice");
        require(dna.ownerOf(1) == BOB, "owner of 1");
        _eq(address(dna).balance, 3 * PRICE, "fees held");
    }

    function test_mintRequiresExactPrice() public {
        vm.startPrank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(IDojoPassDNA.WrongMintPrice.selector, 0, PRICE));
        dna.mint();
        vm.expectRevert(abi.encodeWithSelector(IDojoPassDNA.WrongMintPrice.selector, PRICE + 1, PRICE));
        dna.mint{value: PRICE + 1}();
        vm.stopPrank();
    }

    function test_safeMintToContracts() public {
        address r = address(new Receiver());
        vm.deal(r, 1 ether);
        _mintAs(r);
        address n = address(new NoReceiver());
        vm.deal(n, 1 ether);
        vm.prank(n);
        vm.expectRevert(_err("ERC721: transfer to non ERC721Receiver implementer"));
        dna.mint{value: PRICE}();
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

    // ------------------------------------------------------------ fees
    function test_withdrawSendsFeesToOwner() public {
        _mintAs(ALICE);
        _mintAs(BOB);
        vm.prank(STRANGER);
        vm.expectRevert(_err("Ownable: caller is not the owner"));
        dna.withdraw();
        uint256 before = OWNER.balance;
        vm.prank(OWNER);
        dna.withdraw();
        _eq(OWNER.balance - before, 2 * PRICE, "owner paid");
        _eq(address(dna).balance, 0, "emptied");
    }

    function test_withdrawToRejectingOwnerReverts() public {
        NoReceiver n = new NoReceiver();
        vm.prank(OWNER);
        dna.transferOwnership(address(n));
        _mintAs(ALICE);
        vm.prank(address(n));
        vm.expectRevert(IDojoPassDNA.WithdrawFailed.selector);
        dna.withdraw();
    }

    // ------------------------------------------------------------ metadata (Zerion model)
    function test_tokenURIIsBasePlusId() public {
        _mintAs(ALICE);
        _mintAs(BOB);
        require(_same(dna.tokenURI(1), ""), "empty base -> empty URI");
        vm.prank(OWNER);
        dna.setBaseURI("https://example.test/api/dojo-pass-dna/base-sepolia/");
        require(_same(dna.tokenURI(1), "https://example.test/api/dojo-pass-dna/base-sepolia/1"), "base + id");
        vm.expectRevert(_err("ERC721: invalid token ID"));
        dna.tokenURI(9);
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

    // ------------------------------------------------------------ transfers (standard ERC-721)
    function test_transfersAndApprovalsWork() public {
        uint256 id = _mintAs(ALICE);
        vm.prank(ALICE);
        dna.setApprovalForAll(STRANGER, true);
        require(dna.isApprovedForAll(ALICE, STRANGER), "operator");
        require(!dna.isApprovedForAll(BOB, STRANGER), "no proxy-registry auto-approval");
        vm.prank(STRANGER);
        dna.transferFrom(ALICE, BOB, id);
        require(dna.ownerOf(id) == BOB, "moved");
    }

    // ------------------------------------------------------------ pause
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
        require(!dna.supportsInterface(0xffffffff), "invalid");
    }

    function testFuzz_mintAnyEOA(address who) public {
        vm.assume(who.code.length == 0 && who != address(0) && uint160(who) > 0xff);
        vm.deal(who, 1 ether);
        uint256 id = _mintAs(who);
        require(dna.ownerOf(id) == who, "owner");
    }
}
