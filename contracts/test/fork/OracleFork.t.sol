// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {UniV3ChainlinkOracle, IUniswapV3PoolOracle, IChainlinkFeed} from "../../src/oracle/UniV3ChainlinkOracle.sol";
import {vm} from "../mocks/Vm.sol";

/// @notice Reads REAL Base mainnet state. Runs only when BASE_RPC_URL is set:
///         BASE_RPC_URL=https://mainnet.base.org forge test --match-path test/fork/*
contract OracleForkTest {
    address constant WETH = 0x4200000000000000000000000000000000000006;
    address constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address constant POOL_005 = 0xd0b53D9277642d899DF5C87A3966A349A798F224; // Uniswap v3 WETH/USDC 0.05%
    address constant POOL_03 = 0x6c561B446416E1A00E8E93E221854d6eA4171372; // Uniswap v3 WETH/USDC 0.3%
    address constant CL_ETH_USD = 0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70; // Chainlink ETH/USD

    event Price(string source, uint256 usdcPerWeth);

    function _fork() internal returns (bool) {
        string memory url = vm.envOr("BASE_RPC_URL", string(""));
        if (bytes(url).length == 0) return false;
        vm.createSelectFork(url);
        return true;
    }

    function testFork_realPriceBothPoolsAgreeWithChainlink() public {
        if (!_fork()) return;
        UniV3ChainlinkOracle a = new UniV3ChainlinkOracle(
            IUniswapV3PoolOracle(POOL_005), WETH, USDC, IChainlinkFeed(CL_ETH_USD), 1800, 3600, 200
        );
        UniV3ChainlinkOracle b = new UniV3ChainlinkOracle(
            IUniswapV3PoolOracle(POOL_03), WETH, USDC, IChainlinkFeed(CL_ETH_USD), 1800, 3600, 200
        );
        (uint256 pa,) = a.price(); // reverts on >2% deviation or stale feed
        (uint256 pb,) = b.price();
        (uint256 cl,) = a.chainlinkPrice();
        emit Price("uniswap 0.05% twap", pa);
        emit Price("uniswap 0.3% twap", pb);
        emit Price("chainlink", cl);
        require(pa > 100e6 && pa < 100_000e6, "sane range");
    }
}
