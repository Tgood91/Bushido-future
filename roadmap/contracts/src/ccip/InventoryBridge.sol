// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {CCIPReceiver} from "@chainlink/contracts-ccip/contracts/applications/CCIPReceiver.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/contracts/interfaces/IRouterClient.sol";
import {Client} from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";
import {BushidoFeeVault, IERC20} from "../BushidoFeeVault.sol";

interface IERC20Approve {
    function approve(address spender, uint256 amount) external returns (bool);
}

/// @title InventoryBridge
/// @notice Moves Bushido solver inventory between per-chain BushidoFeeVaults with Chainlink CCIP token
///         transfers. One bridge per chain; each knows its peer bridge on every allowed chain.
///         Outbound: vault.sendInventory -> CCIP send to the peer. Inbound: only from the registered peer
///         on that source chain, only the vault's token, deposited straight into the local vault.
/// @dev    The vault token must be CCIP-supported on both chains (e.g. USDC where Chainlink lists a lane).
///         Fees are paid in native gas from this contract's balance (fund it, or send value with rebalance()).
///         If an inbound delivery reverts, CCIP keeps it for manual re-execution; tokens are not lost.
contract InventoryBridge is CCIPReceiver {
    BushidoFeeVault public immutable vault;
    IERC20 public immutable token;

    address public owner;
    address public pendingOwner;
    address public keeper;
    uint256 public maxPerTransfer;

    mapping(uint64 => address) public peer; // chain selector => InventoryBridge on that chain
    mapping(uint64 => bytes) public extraArgs; // per-destination CCIP extra args (gas limit, ordering)
    mapping(uint64 => uint256) public sentTo;
    mapping(uint64 => uint256) public receivedFrom;
    uint256 public nonce;

    event PeerSet(uint64 indexed chainSelector, address peer, bytes extraArgs);
    event KeeperSet(address keeper);
    event MaxPerTransferSet(uint256 maxPerTransfer);
    event InventoryShipped(bytes32 indexed messageId, uint64 indexed destChain, uint256 amount, uint256 fee, uint256 nonce);
    event InventoryLanded(bytes32 indexed messageId, uint64 indexed sourceChain, uint256 amount, uint256 nonce);
    event NativeWithdrawn(address to, uint256 amount);
    event OwnershipTransferred(address indexed from, address indexed to);

    error NotOwner();
    error NotOwnerOrKeeper();
    error ZeroAmount();
    error ZeroAddress();
    error UnknownPeer(uint64 chainSelector);
    error UnauthorizedSender(uint64 chainSelector, address sender);
    error UnexpectedTokens();
    error OverMaxPerTransfer(uint256 amount, uint256 max);
    error InsufficientFee(uint256 have, uint256 need);
    error ApproveFailed();
    error NativeTransferFailed();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor(address router, BushidoFeeVault _vault, address _owner, uint256 _maxPerTransfer) CCIPReceiver(router) {
        if (address(_vault) == address(0) || _owner == address(0)) revert ZeroAddress();
        vault = _vault;
        token = _vault.usdc();
        owner = _owner;
        maxPerTransfer = _maxPerTransfer;
        emit OwnershipTransferred(address(0), _owner);
        emit MaxPerTransferSet(_maxPerTransfer);
    }

    receive() external payable {}

    // ------------------------------------------------------------------- views
    function buildMessage(uint64 destChain, uint256 amount, uint256 n) public view returns (Client.EVM2AnyMessage memory m) {
        address p = peer[destChain];
        if (p == address(0)) revert UnknownPeer(destChain);
        Client.EVMTokenAmount[] memory tokens = new Client.EVMTokenAmount[](1);
        tokens[0] = Client.EVMTokenAmount({token: address(token), amount: amount});
        m = Client.EVM2AnyMessage({
            receiver: abi.encode(p),
            data: abi.encode(n),
            tokenAmounts: tokens,
            feeToken: address(0), // pay in native
            extraArgs: extraArgs[destChain]
        });
    }

    function quoteFee(uint64 destChain, uint256 amount) external view returns (uint256) {
        return IRouterClient(getRouter()).getFee(destChain, buildMessage(destChain, amount, nonce + 1));
    }

    // ---------------------------------------------------------------- outbound
    /// @notice Ship `amount` of idle inventory from the local vault to the peer vault on `destChain`.
    function rebalance(uint64 destChain, uint256 amount) external payable returns (bytes32 messageId) {
        if (msg.sender != owner && msg.sender != keeper) revert NotOwnerOrKeeper();
        if (amount == 0) revert ZeroAmount();
        if (amount > maxPerTransfer) revert OverMaxPerTransfer(amount, maxPerTransfer);

        uint256 n = ++nonce;
        Client.EVM2AnyMessage memory m = buildMessage(destChain, amount, n);
        IRouterClient router = IRouterClient(getRouter());
        uint256 fee = router.getFee(destChain, m);
        if (address(this).balance < fee) revert InsufficientFee(address(this).balance, fee);

        vault.sendInventory(amount); // vault enforces utilisation + demotes if needed
        if (!IERC20Approve(address(token)).approve(address(router), amount)) revert ApproveFailed();
        messageId = router.ccipSend{value: fee}(destChain, m);

        sentTo[destChain] += amount;
        emit InventoryShipped(messageId, destChain, amount, fee, n);
    }

    // ----------------------------------------------------------------- inbound
    function _ccipReceive(Client.Any2EVMMessage memory m) internal override {
        address expected = peer[m.sourceChainSelector];
        if (expected == address(0)) revert UnknownPeer(m.sourceChainSelector);
        address sender = abi.decode(m.sender, (address));
        if (sender != expected) revert UnauthorizedSender(m.sourceChainSelector, sender);
        if (m.destTokenAmounts.length != 1 || m.destTokenAmounts[0].token != address(token)) revert UnexpectedTokens();

        uint256 amount = m.destTokenAmounts[0].amount;
        if (amount == 0) revert ZeroAmount();
        if (!IERC20Approve(address(token)).approve(address(vault), amount)) revert ApproveFailed();
        vault.seedInventory(amount);

        receivedFrom[m.sourceChainSelector] += amount;
        emit InventoryLanded(m.messageId, m.sourceChainSelector, amount, abi.decode(m.data, (uint256)));
    }

    // ------------------------------------------------------------------- admin
    /// @param _extraArgs e.g. Client._argsToBytes(Client.GenericExtraArgsV2({gasLimit: 300_000, allowOutOfOrderExecution: true}))
    function setPeer(uint64 chainSelector, address _peer, bytes calldata _extraArgs) external onlyOwner {
        peer[chainSelector] = _peer;
        extraArgs[chainSelector] = _extraArgs;
        emit PeerSet(chainSelector, _peer, _extraArgs);
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
