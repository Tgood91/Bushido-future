// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BushidoFeeVault, IERC20} from "./BushidoFeeVault.sol";

interface IERC20Approve {
    function approve(address spender, uint256 amount) external returns (bool);
}

/// @title X402Forwarder
/// @notice The `payTo` address advertised in Bushido's HTTP 402 payment requirements.
///         x402 facilitators settle each "exact" payment by calling USDC's EIP-3009
///         `transferWithAuthorization` with `to = this contract`, so job fees accumulate here.
///         Anyone may `flush()` the batch into BushidoFeeVault as an X402 fee, where it is
///         split 70/10/20 into solver inventory / loss reserve / ops.
/// @dev    No privileged path exists to move USDC anywhere except the immutable vault.
///         Requires `vault.setCollector(address(this), true)`.
contract X402Forwarder {
    IERC20 public immutable usdc;
    BushidoFeeVault public immutable vault;

    address public owner;
    address public pendingOwner;
    /// @notice Minimum batch to flush, so 0.01 USDC payments aren't forwarded one by one.
    uint256 public minFlush;
    uint256 public totalForwarded;
    uint256 public flushCount;

    event Flushed(address indexed caller, uint256 amount, uint256 totalForwarded);
    event MinFlushUpdated(uint256 minFlush);
    event Rescued(address indexed token, address indexed to, uint256 amount);
    event OwnershipTransferred(address indexed from, address indexed to);

    error NotOwner();
    error ZeroAddress();
    error BelowMinFlush(uint256 balance, uint256 minFlush);
    error CannotRescueUsdc();
    error VaultMismatch();
    error ApproveFailed();
    error TransferFailed();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor(BushidoFeeVault _vault, address _owner, uint256 _minFlush) {
        if (address(_vault) == address(0) || _owner == address(0)) revert ZeroAddress();
        vault = _vault;
        usdc = _vault.usdc();
        if (address(usdc) == address(0)) revert VaultMismatch();
        owner = _owner;
        minFlush = _minFlush;
        emit OwnershipTransferred(address(0), _owner);
        emit MinFlushUpdated(_minFlush);
    }

    /// @notice USDC waiting to be forwarded.
    function pending() public view returns (uint256) {
        return usdc.balanceOf(address(this));
    }

    /// @notice True when a keeper should call `flush()`.
    function flushable() external view returns (bool) {
        uint256 bal = pending();
        return bal > 0 && bal >= minFlush;
    }

    /// @notice Permissionless: forward the whole USDC balance into the vault as an X402 fee.
    function flush() external returns (uint256 amount) {
        amount = pending();
        if (amount == 0 || amount < minFlush) revert BelowMinFlush(amount, minFlush);

        totalForwarded += amount;
        flushCount += 1;

        if (!IERC20Approve(address(usdc)).approve(address(vault), amount)) revert ApproveFailed();
        vault.collectFee(BushidoFeeVault.Source.X402, amount);

        emit Flushed(msg.sender, amount, totalForwarded);
    }

    function setMinFlush(uint256 _minFlush) external onlyOwner {
        minFlush = _minFlush;
        emit MinFlushUpdated(_minFlush);
    }

    /// @notice Return tokens sent here by mistake. USDC can never be rescued; it only goes to the vault.
    function rescue(IERC20 token, address to, uint256 amount) external onlyOwner {
        if (address(token) == address(usdc)) revert CannotRescueUsdc();
        if (to == address(0)) revert ZeroAddress();
        if (!token.transfer(to, amount)) revert TransferFailed();
        emit Rescued(address(token), to, amount);
    }

    function transferOwnership(address to) external onlyOwner {
        pendingOwner = to;
    }

    function acceptOwnership() external {
        if (msg.sender != pendingOwner) revert NotOwner();
        emit OwnershipTransferred(owner, msg.sender);
        owner = msg.sender;
        pendingOwner = address(0);
    }
}
