// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice TESTNET stand-in for the live Dojo Pass registry, which exists only on
/// Base and Monad mainnet. It exposes the same selectors (purchasePass, hasDojoPass,
/// passPurchasedAt, isPractitioner, grantPass, revokePass, passFeeInWei), so
/// DojoPassDNA and the metadata backend work against it unchanged.
/// Not a copy of the mainnet source (that was never read); behaviour is inferred.
contract TestDojoPass {
    address public owner;
    uint256 public passFeeInWei;

    mapping(address => bool) public hasDojoPass;
    mapping(address => uint256) public passPurchasedAt;

    error NotOwner();
    error AlreadyPractitioner();
    error InsufficientFee(uint256 sent, uint256 required);

    event PassGranted(address indexed account);
    event PassRevoked(address indexed account);

    constructor(address owner_, uint256 fee) {
        owner = owner_;
        passFeeInWei = fee;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    function isPractitioner(address a) external view returns (bool) {
        return hasDojoPass[a];
    }

    /// @dev Testnet: fee stays in the contract; no treasury plumbing.
    function purchasePass() external payable {
        if (msg.value < passFeeInWei) revert InsufficientFee(msg.value, passFeeInWei);
        _grant(msg.sender);
    }

    function grantPass(address a) external onlyOwner {
        _grant(a);
    }

    function revokePass(address a) external onlyOwner {
        hasDojoPass[a] = false;
        emit PassRevoked(a);
    }

    function _grant(address a) private {
        if (hasDojoPass[a]) revert AlreadyPractitioner();
        hasDojoPass[a] = true;
        passPurchasedAt[a] = block.timestamp;
        emit PassGranted(a);
    }
}
