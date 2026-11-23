// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BushidoFeeVault, IERC20} from "../BushidoFeeVault.sol";

/// @dev Minimal slice of Hyperlane's TokenRouter (HypERC20 / HypERC20Collateral warp routes).
struct WarpQuote {
    address token; // address(0) = native gas
    uint256 amount;
}

interface IWarpRoute {
    function token() external view returns (address);
    function quoteTransferRemote(uint32 destination, bytes32 recipient, uint256 amount)
        external
        view
        returns (WarpQuote[] memory);
    function transferRemote(uint32 destination, bytes32 recipient, uint256 amount)
        external
        payable
        returns (bytes32 messageId);
}

interface IERC20Approve {
    function approve(address spender, uint256 amount) external returns (bool);
}

/// @title WarpInventoryBridge
/// @notice Moves Bushido solver inventory between per-chain BushidoFeeVaults over an open-source
///         Hyperlane warp route (permissionless; deployable on any EVM chain, works with our own test tokens).
///         Outbound: vault.sendInventory -> warpRoute.transferRemote straight to the destination VAULT.
///         Inbound: the warp route mints/releases tokens to that vault; anyone calls vault.absorbSurplus().
///         No callback is needed, so the same pattern works for any bridge that delivers to an address.
/// @dev    Cross-chain balances are reconciled offchain from InventoryShipped / SurplusAbsorbed events.
///         Routes with token-denominated fees are refused, so the destination always receives `amount`.
contract WarpInventoryBridge {
    BushidoFeeVault public immutable vault;
    IWarpRoute public immutable warpRoute;
    IERC20 public immutable token;

    address public owner;
    address public pendingOwner;
    address public keeper;
    uint256 public maxPerTransfer;

    mapping(uint32 => address) public remoteVault; // Hyperlane domain => BushidoFeeVault on that chain
    mapping(uint32 => uint256) public shippedTo;

    event RemoteVaultSet(uint32 indexed domain, address vault);
    event KeeperSet(address keeper);
    event MaxPerTransferSet(uint256 maxPerTransfer);
    event InventoryShipped(bytes32 indexed messageId, uint32 indexed domain, address indexed remoteVault, uint256 amount, uint256 gasPaid);
    event NativeWithdrawn(address to, uint256 amount);
    event OwnershipTransferred(address indexed from, address indexed to);

    error NotOwner();
    error NotOwnerOrKeeper();
    error ZeroAmount();
    error ZeroAddress();
    error TokenMismatch();
    error UnknownDomain(uint32 domain);
    error OverMaxPerTransfer(uint256 amount, uint256 max);
    error UnsupportedTokenFee(uint256 tokenFee);
    error InsufficientGas(uint256 have, uint256 need);
    error ApproveFailed();
    error NativeTransferFailed();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor(BushidoFeeVault _vault, IWarpRoute _warpRoute, address _owner, uint256 _maxPerTransfer) {
        if (address(_vault) == address(0) || address(_warpRoute) == address(0) || _owner == address(0)) revert ZeroAddress();
        vault = _vault;
        warpRoute = _warpRoute;
        token = _vault.usdc();
        if (_warpRoute.token() != address(token)) revert TokenMismatch();
        owner = _owner;
        maxPerTransfer = _maxPerTransfer;
        emit OwnershipTransferred(address(0), _owner);
        emit MaxPerTransferSet(_maxPerTransfer);
    }

    receive() external payable {}

    // ------------------------------------------------------------------- views
    /// @return gas native gas to pay; tokenFee token-denominated fees beyond `amount` (must be 0)
    function quote(uint32 domain, uint256 amount) public view returns (uint256 gas, uint256 tokenFee) {
        address rv = remoteVault[domain];
        if (rv == address(0)) revert UnknownDomain(domain);
        WarpQuote[] memory q = warpRoute.quoteTransferRemote(domain, bytes32(uint256(uint160(rv))), amount);
        uint256 tokenTotal;
        for (uint256 i = 0; i < q.length; i++) {
            if (q[i].token == address(0)) gas += q[i].amount;
            else if (q[i].token == address(token)) tokenTotal += q[i].amount;
        }
        tokenFee = tokenTotal > amount ? tokenTotal - amount : 0;
    }

    // ---------------------------------------------------------------- outbound
    function rebalance(uint32 domain, uint256 amount) external payable returns (bytes32 messageId) {
        if (msg.sender != owner && msg.sender != keeper) revert NotOwnerOrKeeper();
        if (amount == 0) revert ZeroAmount();
        if (amount > maxPerTransfer) revert OverMaxPerTransfer(amount, maxPerTransfer);
        (uint256 gas, uint256 tokenFee) = quote(domain, amount);
        if (tokenFee != 0) revert UnsupportedTokenFee(tokenFee);
        if (address(this).balance < gas) revert InsufficientGas(address(this).balance, gas);

        vault.sendInventory(amount); // utilisation cap + phase demotion enforced by the vault
        if (!IERC20Approve(address(token)).approve(address(warpRoute), amount)) revert ApproveFailed();
        address rv = remoteVault[domain];
        messageId = warpRoute.transferRemote{value: gas}(domain, bytes32(uint256(uint160(rv))), amount);

        shippedTo[domain] += amount;
        emit InventoryShipped(messageId, domain, rv, amount, gas);
    }

    // ------------------------------------------------------------------- admin
    function setRemoteVault(uint32 domain, address _vault) external onlyOwner {
        remoteVault[domain] = _vault;
        emit RemoteVaultSet(domain, _vault);
    }

    function setKeeper(address _keeper) external onlyOwner {
        keeper = _keeper;
        emit KeeperSet(_keeper);
    }

    function setMaxPerTransfer(uint256 _max) external onlyOwner {
        maxPerTransfer = _max;
        emit MaxPerTransferSet(_max);
    }

    function withdrawNative(address payable to, uint256 amount) external onlyOwner {
        (bool ok,) = to.call{value: amount}("");
        if (!ok) revert NativeTransferFailed();
        emit NativeWithdrawn(to, amount);
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
