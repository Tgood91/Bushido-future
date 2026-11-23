// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {
    UniV3ChainlinkOracle,
    IUniswapV3PoolOracle,
    IChainlinkFeed,
    IPriceOracle
} from "../src/oracle/UniV3ChainlinkOracle.sol";
import {OracleSwap} from "../src/OracleSwap.sol";
import {BushidoFeeVault, IERC20} from "../src/BushidoFeeVault.sol";
import {TestToken} from "../src/testnet/TestToken.sol";
import {MockUSDC} from "./mocks/MockUSDC.sol";
import {vm} from "./mocks/Vm.sol";

contract MockPool {
    address public token0;
    address public token1;
    int56 public avgTick;
    int56 public remainder; // added to the cumulative delta to test rounding

    constructor(address t0, address t1) {
        token0 = t0;
        token1 = t1;
    }

    function setTick(int56 t) external {
        avgTick = t;
    }

    function setRemainder(int56 r) external {
        remainder = r;
    }

    function observe(uint32[] calldata ago) external view returns (int56[] memory c, uint160[] memory s) {
        c = new int56[](2);
        s = new uint160[](2);
        c[0] = 1_000_000_000; // arbitrary base
        c[1] = c[0] + avgTick * int56(uint56(ago[0])) + remainder;
    }
}

contract MockFeed {
    int256 public answer;
    uint256 public updatedAt;

    function set(int256 a, uint256 t) external {
        answer = a;
        updatedAt = t;
    }

    function decimals() external pure returns (uint8) {
        return 8;
    }

    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        return (1, answer, updatedAt, updatedAt, 1);
    }
}

contract OracleTest {
    address constant WETH = address(0x4200000000000000000000000000000000000006);
    address constant USDC = address(0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913);
    uint256 constant EXPECTED = 1_717_337_187; // 1.0001^-201835 * 1e18 (computed offchain)

    MockPool pool;
    MockFeed feed;
    UniV3ChainlinkOracle oracle;

    function setUp() public {
        vm.warp(1_800_000_000);
        pool = new MockPool(WETH, USDC);
        pool.setTick(-201835);
        feed = new MockFeed();
        feed.set(1717_00000000, block.timestamp); // $1,717.00, 8 dp
        oracle = _oracle(address(pool));
    }

    function _oracle(address p) internal returns (UniV3ChainlinkOracle) {
        return new UniV3ChainlinkOracle(
            IUniswapV3PoolOracle(p), WETH, USDC, IChainlinkFeed(address(feed)), 1800, 3600, 200
        );
    }

    function _near(uint256 a, uint256 b, uint256 tolBps, string memory m) internal pure {
        uint256 d = a > b ? a - b : b - a;
        require(d * 10_000 <= b * tolBps, m);
    }

    function test_tickToPrice_wethToken0() public view {
        _near(oracle.uniswapPrice(), EXPECTED, 1, "uniswap price");
        require(oracle.wethIsToken0(), "orientation");
    }

    function test_tickToPrice_wethToken1() public {
        MockPool flipped = new MockPool(USDC, WETH);
        flipped.setTick(201835);
        UniV3ChainlinkOracle o = _oracle(address(flipped));
        require(!o.wethIsToken0(), "orientation");
        _near(o.uniswapPrice(), EXPECTED, 1, "flipped price");
    }

    function test_negativeTickRoundsDown() public {
        // cumulative delta not divisible by window must round toward -inf, like Uniswap's OracleLibrary
        MockPool p = new MockPool(WETH, USDC);
        p.setTick(-201835);
        UniV3ChainlinkOracle o = _oracle(address(p));
        require(o.twapTick() == -201835, "exact tick");
        p.setRemainder(-1); // delta = -201835*1800 - 1  ->  -201835.0005  ->  floor = -201836
        require(o.twapTick() == -201836, "rounds toward -inf");
        p.setRemainder(1); // -201834.9994 -> floor = -201835 (not truncated toward zero)
        require(o.twapTick() == -201835, "positive remainder floors");
    }

    function test_chainlinkScaledTo6dp() public view {
        (uint256 cl,) = oracle.chainlinkPrice();
        require(cl == 1_717_000_000, "8dp -> 6dp");
    }

    function test_priceReturnsUniswapWhenSourcesAgree() public view {
        (uint256 px, uint256 t) = oracle.price();
        _near(px, EXPECTED, 1, "price");
        require(t == block.timestamp, "timestamp");
    }

    function test_revertsOnDeviation() public {
        feed.set(1600_00000000, block.timestamp); // ~7% below the pool
        vm.expectRevert(
            abi.encodeWithSelector(UniV3ChainlinkOracle.PriceDeviation.selector, oracle.uniswapPrice(), 1_600_000_000, 733)
        );
        oracle.price();
    }

    function test_revertsOnStaleFeed() public {
        uint256 old = block.timestamp - 3601;
        feed.set(1717_00000000, old);
        vm.expectRevert(abi.encodeWithSelector(UniV3ChainlinkOracle.StaleFeed.selector, old, 3600));
        oracle.price();
    }

    function test_revertsOnBadAnswer() public {
        feed.set(0, block.timestamp);
        vm.expectRevert(UniV3ChainlinkOracle.BadFeedAnswer.selector);
        oracle.price();
    }

    function test_rejectsWrongPool() public {
        MockPool wrong = new MockPool(WETH, address(0xdead));
        vm.expectRevert(UniV3ChainlinkOracle.PoolTokenMismatch.selector);
        _oracle(address(wrong));
    }
}

contract FixedOracle is IPriceOracle {
    uint256 public px;

    function set(uint256 p) external {
        px = p;
    }

    function price() external view returns (uint256, uint256) {
        return (px, block.timestamp);
    }
}

contract OracleSwapTest {
    uint256 constant PX = 1_717_000_000; // 1,717 USDC per WETH
    address constant OWNER = address(0xB051D0);
    address constant TRADER = address(0x7EAD);

    MockUSDC usdc;
    TestToken weth;
    BushidoFeeVault vault;
    FixedOracle oracle;
    OracleSwap market;

    function setUp() public {
        usdc = new MockUSDC();
        weth = new TestToken("Bushido Test WETH", "tWETH", 18);
        vault = new BushidoFeeVault(IERC20(address(usdc)), OWNER, 6_250e6, 25_000e6, 500e6);
        oracle = new FixedOracle();
        oracle.set(PX);
        market = new OracleSwap(IERC20(address(weth)), oracle, vault, OWNER, 25); // 25 bps
        vm.prank(OWNER);
        vault.setCollector(address(market), true);

        usdc.mint(address(market), 100_000e6);
        weth.mint(address(market), 100e18);
        usdc.mint(TRADER, 10_000e6);
        weth.mint(TRADER, 10e18);
        vm.startPrank(TRADER);
        usdc.approve(address(market), type(uint256).max);
        weth.approve(address(market), type(uint256).max);
        vm.stopPrank();
    }

    function test_sellWethAtOraclePriceAndFeeToVault() public {
        vm.prank(TRADER);
        uint256 out = market.sellWeth(1e18, 0);
        // gross 1,717.000000; fee 25 bps = 4.292500; out = 1,712.707500
        require(out == 1_712_707_500, "usdc out");
        require(usdc.balanceOf(TRADER) == 10_000e6 + out, "trader paid");
        require(vault.totalCollected(BushidoFeeVault.Source.EXECUTION) == 4_292_500, "fee to vault");
        require(vault.inventory() == 3_004_750, "70% of fee retained");
        require(usdc.balanceOf(address(vault)) == vault.accounted(), "vault invariant");
    }

    function test_buyWethAtOraclePriceAndFeeToVault() public {
        vm.prank(TRADER);
        uint256 out = market.buyWeth(1_717e6, 0);
        // fee 4.2925 USDC; (1,717 - 4.2925) / 1,717 = 0.9975 WETH
        require(out == 0.9975e18, "weth out");
        require(vault.totalCollected(BushidoFeeVault.Source.EXECUTION) == 4_292_500, "fee to vault");
    }

    function test_slippageProtection() public {
        vm.prank(TRADER);
        vm.expectRevert(abi.encodeWithSelector(OracleSwap.Slippage.selector, 1_712_707_500, 1_716e6));
        market.sellWeth(1e18, 1_716e6);
    }

    function test_priceMoveFollowsOracle() public {
        oracle.set(2_000e6);
        (uint256 out,,) = market.quoteSellWeth(1e18);
        require(out == 1_995e6, "repriced");
    }

    function test_insufficientLiquidity() public {
        weth.mint(TRADER, 1_000e18);
        vm.prank(TRADER);
        vm.expectRevert(OracleSwap.InsufficientLiquidity.selector);
        market.sellWeth(100e18, 0);
    }

    function test_feeCapped() public {
        vm.prank(OWNER);
        vm.expectRevert(OracleSwap.BadFee.selector);
        market.setFee(101);
    }

    function test_marketNeedsCollectorRights() public {
        vm.prank(OWNER);
        vault.setCollector(address(market), false);
        vm.prank(TRADER);
        vm.expectRevert(BushidoFeeVault.NotCollector.selector);
        market.sellWeth(1e18, 0);
    }
}
