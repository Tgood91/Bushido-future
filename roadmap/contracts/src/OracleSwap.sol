// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BushidoFeeVault, IERC20} from "./BushidoFeeVault.sol";
import {IPriceOracle} from "./oracle/UniV3ChainlinkOracle.sol";

interface IERC20Approve {
    function approve(address spender, uint256 amount) external returns (bool);
}

/// @title OracleSwap
/// @notice Test market: swaps WETH <-> USDC from its own inventory at the oracle price (no AMM curve).
///         The execution fee (bps of USDC notional) is sent to BushidoFeeVault as an EXECUTION fee,
///         i.e. this is the "router fee hook" feeding solver inventory. Requires vault collector rights.
/// @dev    For testnets/forks. No LP shares: the owner funds and withdraws inventory directly.
contract OracleSwap {
    IERC20 public immutable usdc;
    IERC20 public immutable weth;
    IPriceOracle public immutable oracle;
    BushidoFeeVault public immutable vault;

    address public owner;
    uint16 public feeBps;
    uint16 public constant MAX_FEE_BPS = 100;

    event Swap(address indexed trader, bool sellWeth, uint256 amountIn, uint256 amountOut, uint256 fee, uint256 price);
    event FeeUpdated(uint16 feeBps);
    event Withdrawn(address indexed token, address indexed to, uint256 amount);

    error NotOwner();
    error ZeroAmount();
    error BadFee();
    error Slippage(uint256 out, uint256 minOut);
    error InsufficientLiquidity();
    error TransferFailed();
    error VaultMismatch();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor(IERC20 _weth, IPriceOracle _oracle, BushidoFeeVault _vault, address _owner, uint16 _feeBps) {
        if (_feeBps > MAX_FEE_BPS) revert BadFee();
        weth = _weth;
        oracle = _oracle;
        vault = _vault;
        usdc = _vault.usdc();
        if (address(usdc) == address(0)) revert VaultMismatch();
        owner = _owner;
        feeBps = _feeBps;
        emit FeeUpdated(_feeBps);
    }

    // ------------------------------------------------------------------ quotes
    function quoteSellWeth(uint256 wethIn) public view returns (uint256 usdcOut, uint256 fee, uint256 px) {
        (px,) = oracle.price();
        uint256 gross = (wethIn * px) / 1e18;
        fee = (gross * feeBps) / 10_000;
        usdcOut = gross - fee;
    }

    function quoteBuyWeth(uint256 usdcIn) public view returns (uint256 wethOut, uint256 fee, uint256 px) {
        (px,) = oracle.price();
        fee = (usdcIn * feeBps) / 10_000;
        wethOut = ((usdcIn - fee) * 1e18) / px;
    }

    // ------------------------------------------------------------------- swaps
    function sellWeth(uint256 wethIn, uint256 minUsdcOut) external returns (uint256 usdcOut) {
        if (wethIn == 0) revert ZeroAmount();
        uint256 fee;
        uint256 px;
        (usdcOut, fee, px) = quoteSellWeth(wethIn);
        if (usdcOut < minUsdcOut) revert Slippage(usdcOut, minUsdcOut);
        if (usdc.balanceOf(address(this)) < usdcOut + fee) revert InsufficientLiquidity();

        _pull(weth, msg.sender, wethIn);
        _push(usdc, msg.sender, usdcOut);
        _payFee(fee);
        emit Swap(msg.sender, true, wethIn, usdcOut, fee, px);
    }

    function buyWeth(uint256 usdcIn, uint256 minWethOut) external returns (uint256 wethOut) {
        if (usdcIn == 0) revert ZeroAmount();
        uint256 fee;
        uint256 px;
        (wethOut, fee, px) = quoteBuyWeth(usdcIn);
        if (wethOut < minWethOut) revert Slippage(wethOut, minWethOut);
        if (weth.balanceOf(address(this)) < wethOut) revert InsufficientLiquidity();

        _pull(usdc, msg.sender, usdcIn);
        _push(weth, msg.sender, wethOut);
        _payFee(fee);
        emit Swap(msg.sender, false, usdcIn, wethOut, fee, px);
    }

    // ------------------------------------------------------------------- admin
    function setFee(uint16 _feeBps) external onlyOwner {
        if (_feeBps > MAX_FEE_BPS) revert BadFee();
        feeBps = _feeBps;
        emit FeeUpdated(_feeBps);
    }

    function withdraw(IERC20 token, address to, uint256 amount) external onlyOwner {
        _push(token, to, amount);
        emit Withdrawn(address(token), to, amount);
    }

    // ---------------------------------------------------------------- internal
    function _payFee(uint256 fee) internal {
        if (fee == 0) return;
        if (!IERC20Approve(address(usdc)).approve(address(vault), fee)) revert TransferFailed();
        vault.collectFee(BushidoFeeVault.Source.EXECUTION, fee);
    }

    function _pull(IERC20 token, address from, uint256 amount) internal {
        if (!token.transferFrom(from, address(this), amount)) revert TransferFailed();
    }

    function _push(IERC20 token, address to, uint256 amount) internal {
        if (!token.transfer(to, amount)) revert TransferFailed();
    }
}
