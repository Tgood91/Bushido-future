// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "../BushidoFeeVault.sol";
import {IWarpRoute} from "../bridge/WarpInventoryBridge.sol";

interface IHyperlaneMailbox {
    function localDomain() external view returns (uint32);
    function dispatch(uint32 destinationDomain, bytes32 recipientAddress, bytes calldata messageBody)
        external
        payable
        returns (bytes32 messageId);
    function quoteDispatch(uint32 destinationDomain, bytes32 recipientAddress, bytes calldata messageBody)
        external
        view
        returns (uint256 fee);
}

interface IERC20Approve {
    function approve(address spender, uint256 amount) external returns (bool);
}

/// @title IntentSettler
/// @notice Cross-chain transfer intents between Bushido chains, settled over Hyperlane. One per chain.
///         Origin: a user `open`s an order (deposit amountOut + 25 bps). Destination: a solver `fill`s it
///         (pays the recipient) and this contract sends a Hyperlane message back to the origin settler.
///         Origin: `handle` checks the message came from the enrolled peer and matches the order hash, then
///         anyone may `repay`: the deposit goes over the warp route to the destination chain's vault, where
///         the solver closes its vault fill with `settleFillFromBalance`. The 25 bps is the vault's profit.
/// @dev    The user never trusts the solver: a fill with wrong parameters doesn't match the stored hash and
///         is ignored. Unfilled orders can be refunded after deadline + REFUND_GRACE.
contract IntentSettler {
    uint16 public constant FEE_BPS = 25;
    uint64 public constant REFUND_GRACE = 1 hours;

    enum Status {
        None,
        Open,
        Filled,
        Repaid,
        Refunded
    }

    struct Params {
        uint32 origin;
        uint32 dest;
        uint256 nonce;
        address user;
        address recipient;
        uint256 amountIn; // amountOut + fee, deposited on origin
        uint256 amountOut; // delivered on dest
        uint64 deadline; // last timestamp a fill is accepted on dest
    }

    struct Order {
        Status status;
        uint32 dest;
        address user;
        uint64 deadline;
        uint256 amountIn;
        address solver;
    }

    IHyperlaneMailbox public immutable mailbox;
    uint32 public immutable localDomain;
    IERC20 public immutable token;
    IWarpRoute public immutable warpRoute;

    address public owner;
    address public pendingOwner;
    address public interchainSecurityModule; // 0 = mailbox default ISM
    uint256 public nonce;

    mapping(uint32 => bytes32) public peer; // settler on each remote domain
    mapping(uint32 => address) public remoteVault; // vault on each remote domain that fronts fills
    mapping(bytes32 => Order) public orders; // origin side, by order hash
    mapping(bytes32 => address) public filledBy; // destination side, by order hash

    event Opened(bytes32 indexed orderHash, Params params);
    event Filled(bytes32 indexed orderHash, address indexed solver, address recipient, uint256 amountOut, bytes32 messageId);
    event FillConfirmed(bytes32 indexed orderHash, uint32 indexed fromDomain, address solver);
    event FillIgnored(bytes32 indexed orderHash, uint32 indexed fromDomain, Status status);
    event Repaid(bytes32 indexed orderHash, uint32 indexed dest, address vault, uint256 amount, bytes32 messageId);
    event Refunded(bytes32 indexed orderHash, address user, uint256 amount);
    event PeerSet(uint32 indexed domain, bytes32 peer, address remoteVault);
    event IsmSet(address ism);
    event OwnershipTransferred(address indexed from, address indexed to);

    error NotOwner();
    error NotMailbox();
    error UnknownDomain(uint32 domain);
    error UnauthorizedSender(uint32 domain, bytes32 sender);
    error ZeroAmount();
    error BadDeadline();
    error WrongDestination();
    error Expired();
    error AlreadyFilled();
    error NotFilled();
    error NotRefundable();
    error InsufficientMessageFee(uint256 sent, uint256 needed);
    error TransferFailed();
    error TokenMismatch();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor(IHyperlaneMailbox _mailbox, IWarpRoute _warpRoute, address _owner) {
        mailbox = _mailbox;
        localDomain = _mailbox.localDomain();
        warpRoute = _warpRoute;
        token = IERC20(_warpRoute.token());
        owner = _owner;
        emit OwnershipTransferred(address(0), _owner);
    }

    receive() external payable {}

    // ------------------------------------------------------------------- views
    function hashOrder(Params memory p) public pure returns (bytes32) {
        return keccak256(abi.encode(p));
    }

    function feeFor(uint256 amountOut) public pure returns (uint256) {
        return (amountOut * FEE_BPS + 9_999) / 10_000; // round up
    }

    function quoteFill(Params calldata p) external view returns (uint256) {
        return mailbox.quoteDispatch(p.origin, peer[p.origin], abi.encode(hashOrder(p), msg.sender));
    }

    // ---------------------------------------------------------------- origin
    function open(uint32 dest, address recipient, uint256 amountOut, uint64 deadline)
        external
        returns (bytes32 h, Params memory p)
    {
        if (peer[dest] == bytes32(0)) revert UnknownDomain(dest);
        if (amountOut == 0 || recipient == address(0)) revert ZeroAmount();
        if (deadline <= block.timestamp) revert BadDeadline();
        uint256 amountIn = amountOut + feeFor(amountOut);
        if (!token.transferFrom(msg.sender, address(this), amountIn)) revert TransferFailed();

        p = Params(localDomain, dest, ++nonce, msg.sender, recipient, amountIn, amountOut, deadline);
        h = hashOrder(p);
        orders[h] = Order(Status.Open, dest, msg.sender, deadline, amountIn, address(0));
        emit Opened(h, p);
    }

    /// @notice Hyperlane delivery of a fill confirmation from the destination settler.
    function handle(uint32 fromDomain, bytes32 sender, bytes calldata body) external payable {
        if (msg.sender != address(mailbox)) revert NotMailbox();
        if (sender == bytes32(0) || sender != peer[fromDomain]) revert UnauthorizedSender(fromDomain, sender);
        (bytes32 h, address solver) = abi.decode(body, (bytes32, address));
        Order storage o = orders[h];
        if (o.status != Status.Open || o.dest != fromDomain) {
            emit FillIgnored(h, fromDomain, o.status); // don't revert: a revert would be retried forever
            return;
        }
        o.status = Status.Filled;
        o.solver = solver;
        emit FillConfirmed(h, fromDomain, solver);
    }

    /// @notice Permissionless: send the deposit (principal + fee) to the destination vault that fronted the fill.
    ///         Pay the warp route's interchain gas with msg.value.
    function repay(bytes32 h) external payable returns (bytes32 messageId) {
        Order storage o = orders[h];
        if (o.status != Status.Filled) revert NotFilled();
        address rv = remoteVault[o.dest];
        if (rv == address(0)) revert UnknownDomain(o.dest);
        o.status = Status.Repaid;
        if (!IERC20Approve(address(token)).approve(address(warpRoute), o.amountIn)) revert TransferFailed();
        messageId = warpRoute.transferRemote{value: msg.value}(o.dest, bytes32(uint256(uint160(rv))), o.amountIn);
        emit Repaid(h, o.dest, rv, o.amountIn, messageId);
    }

    function refund(bytes32 h) external {
        Order storage o = orders[h];
        if (o.status != Status.Open || block.timestamp <= uint256(o.deadline) + REFUND_GRACE) revert NotRefundable();
        o.status = Status.Refunded;
        if (!token.transfer(o.user, o.amountIn)) revert TransferFailed();
        emit Refunded(h, o.user, o.amountIn);
    }

    // ----------------------------------------------------------- destination
    /// @notice Solver delivers `amountOut` to the recipient from its own balance (e.g. drawn from the vault)
    ///         and confirms to the origin over Hyperlane. msg.value pays the message fee.
    function fill(Params calldata p) external payable returns (bytes32 messageId) {
        if (p.dest != localDomain) revert WrongDestination();
        bytes32 originSettler = peer[p.origin];
        if (originSettler == bytes32(0)) revert UnknownDomain(p.origin);
        if (block.timestamp > p.deadline) revert Expired();
        bytes32 h = hashOrder(p);
        if (filledBy[h] != address(0)) revert AlreadyFilled();
        filledBy[h] = msg.sender;

        if (!token.transferFrom(msg.sender, p.recipient, p.amountOut)) revert TransferFailed();
        bytes memory body = abi.encode(h, msg.sender);
        uint256 needed = mailbox.quoteDispatch(p.origin, originSettler, body);
        if (msg.value < needed) revert InsufficientMessageFee(msg.value, needed);
        messageId = mailbox.dispatch{value: msg.value}(p.origin, originSettler, body);
        emit Filled(h, msg.sender, p.recipient, p.amountOut, messageId);
    }

    // ------------------------------------------------------------------- admin
    function setPeer(uint32 domain, address _peer, address _remoteVault) external onlyOwner {
        peer[domain] = bytes32(uint256(uint160(_peer)));
        remoteVault[domain] = _remoteVault;
        emit PeerSet(domain, peer[domain], _remoteVault);
    }

    /// @notice 0 uses the Mailbox default ISM (live testnets). Local forks use a test ISM.
    function setInterchainSecurityModule(address ism) external onlyOwner {
        interchainSecurityModule = ism;
        emit IsmSet(ism);
    }

    function withdrawNative(address payable to, uint256 amount) external onlyOwner {
        (bool ok,) = to.call{value: amount}("");
        if (!ok) revert TransferFailed();
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
