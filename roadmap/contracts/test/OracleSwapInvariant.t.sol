// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {OracleSwap} from "../src/OracleSwap.sol";
import {IPriceOracle} from "../src/oracle/UniV3ChainlinkOracle.sol";
import {BushidoFeeVault, IERC20} from "../src/BushidoFeeVault.sol";
import {TestToken} from "../src/testnet/TestToken.sol";
import {MockUSDC} from "./mocks/MockUSDC.sol";
import {vm} from "./mocks/Vm.sol";

contract SettableOracle is IPriceOracle {
    uint256 public px;

    function set(uint256 p) external {
        px = p;
    }

    function price() external view returns (uint256, uint256) {
        return (px, block.timestamp);
    }
}

/// @notice OracleSwap prices at the oracle, not on an x*y curve, so the "k" it must preserve is the
///         value of its inventory at the oracle price: K = weth * px / 1e18 + usdc (USDC base units).
///         Every swap must leave K >= K_before (rounding may only favour the pool), and the pool plus
///         the fee vault together must gain at least the fee charged.
contract OracleSwapInvariantTest {
    address constant OWNER = address(0xB051D0);
    address constant TRADER = address(0x7EAD);

    uint256 constant POOL_WETH = 1_000_000e18;
    uint256 constant POOL_USDC = 1e15; // 1B USDC

    MockUSDC usdc;
    TestToken weth;
    BushidoFeeVault vault;
    SettableOracle oracle;
    OracleSwap market;

    function setUp() public {
        usdc = new MockUSDC();
        weth = new TestToken("Bushido Test WETH", "tWETH", 18);
        vault = new BushidoFeeVault(IERC20(address(usdc)), OWNER, 6_250e6, 25_000e6, 500e6);
        oracle = new SettableOracle();
        oracle.set(1_717e6);
        market = new OracleSwap(IERC20(address(weth)), oracle, vault, OWNER, 25);
        vm.prank(OWNER);
        vault.setCollector(address(market), true);

        usdc.mint(address(market), POOL_USDC);
        weth.mint(address(market), POOL_WETH);
        vm.startPrank(TRADER);
        usdc.approve(address(market), type(uint256).max);
        weth.approve(address(market), type(uint256).max);
        vm.stopPrank();
    }

    function testFuzz_SwapNeverDecreasesK(uint256 pxSeed, uint16 feeSeed, uint256 seed) public {
        uint256 px = _bound(pxSeed, 1e4, 1e12); // $0.01 .. $1,000,000 per WETH
        oracle.set(px);
        uint16 fee = uint16(_bound(feeSeed, 0, market.MAX_FEE_BPS()));
        vm.prank(OWNER);
        market.setFee(fee);

        // A short random sequence of swaps in either direction, each checked on its own.
        for (uint256 i; i < 4; ++i) {
            seed = uint256(keccak256(abi.encode(seed, i)));
            bool sell = seed & 1 == 0;
            uint256 kBefore = _k(px);
            uint256 sysBefore = kBefore + usdc.balanceOf(address(vault));
            uint256 feePaid;

            if (sell) {
                // Cap so USDC inventory always covers the payout.
                uint256 maxIn = (usdc.balanceOf(address(market)) * 1e18) / px;
                if (maxIn > 10_000e18) maxIn = 10_000e18;
                if (maxIn == 0) continue;
                uint256 amt = _bound(seed >> 8, 1, maxIn);
                weth.mint(TRADER, amt);
                (,, uint256 qpx) = market.quoteSellWeth(amt);
                uint256 gross = (amt * qpx) / 1e18;
                feePaid = (gross * fee) / 10_000;
                vm.prank(TRADER);
                market.sellWeth(amt, 0);
            } else {
                uint256 maxIn = (weth.balanceOf(address(market)) * px) / 1e18;
                if (maxIn > 10_000_000e6) maxIn = 10_000_000e6;
                if (maxIn == 0) continue;
                uint256 amt = _bound(seed >> 8, 1, maxIn);
                (uint256 out, uint256 f,) = market.quoteBuyWeth(amt);
                if (out == 0) continue; // dust that buys nothing is still allowed; skip, nothing to check
                feePaid = f;
                usdc.mint(TRADER, amt);
                vm.prank(TRADER);
                market.buyWeth(amt, 0);
            }

            uint256 kAfter = _k(px);
            require(kAfter >= kBefore, "K decreased");
            require(kAfter + usdc.balanceOf(address(vault)) >= sysBefore + feePaid, "system K short of fee");
        }
    }

    function _k(uint256 px) internal view returns (uint256) {
        return (weth.balanceOf(address(market)) * px) / 1e18 + usdc.balanceOf(address(market));
    }

    function _bound(uint256 x, uint256 lo, uint256 hi) internal pure returns (uint256) {
        return lo + (x % (hi - lo + 1));
    }
}
