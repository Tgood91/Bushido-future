// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BushidoFeeVault, IERC20} from "../src/BushidoFeeVault.sol";
import {X402Forwarder} from "../src/X402Forwarder.sol";
import {OracleSwap} from "../src/OracleSwap.sol";
import {UniV3ChainlinkOracle, IUniswapV3PoolOracle, IChainlinkFeed} from "../src/oracle/UniV3ChainlinkOracle.sol";
import {TestToken} from "../src/testnet/TestToken.sol";
import {MockUSDC} from "../test/mocks/MockUSDC.sol";
import {vm} from "../test/mocks/Vm.sol";

/// @notice For an anvil fork of Base mainnet: tWETH/tUSDC test tokens priced by the REAL Uniswap v3
///         WETH/USDC TWAP (cross-checked with Chainlink ETH/USD). Swap fees flow into the vault.
///   anvil --fork-url https://mainnet.base.org
///   DEPLOYER=0xf39F...2266 forge script script/DeployOracleMarket.s.sol:DeployOracleMarket \
///     --rpc-url http://127.0.0.1:8545 --broadcast --unlocked --sender $DEPLOYER
contract DeployOracleMarket {
    address constant WETH = 0x4200000000000000000000000000000000000006;
    address constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address constant POOL_WETH_USDC_005 = 0xd0b53D9277642d899DF5C87A3966A349A798F224;
    address constant CHAINLINK_ETH_USD = 0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70;

    function run()
        external
        returns (MockUSDC tusdc, TestToken tweth, BushidoFeeVault vault, X402Forwarder fwd, UniV3ChainlinkOracle oracle, OracleSwap market)
    {
        address deployer = vm.envAddress("DEPLOYER");
        vm.startBroadcast(deployer);
        tusdc = new MockUSDC();
        tweth = new TestToken("Bushido Test WETH", "tWETH", 18);
        vault = new BushidoFeeVault(IERC20(address(tusdc)), deployer, 6_250e6, 25_000e6, 500e6);
        fwd = new X402Forwarder(vault, deployer, 1e6);
        oracle = new UniV3ChainlinkOracle(
            IUniswapV3PoolOracle(POOL_WETH_USDC_005), WETH, USDC, IChainlinkFeed(CHAINLINK_ETH_USD), 1800, 3600, 200
        );
        market = new OracleSwap(IERC20(address(tweth)), oracle, vault, deployer, 10); // 10 bps execution fee
        vault.setCollector(address(fwd), true);
        vault.setCollector(address(market), true);

        tusdc.mint(address(market), 1_000_000e6); // market inventory
        tweth.mint(address(market), 500e18);
        tusdc.mint(deployer, 100_000e6); // trader balances
        tweth.mint(deployer, 50e18);
        vm.stopBroadcast();
    }
}
