// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";
import {FlashLeverage} from "../src/core/FlashLeverage/FlashLeverage.sol";
import {MarketConfig} from "../src/core/structs/MarketConfig.sol";

contract DeployFlashLeverage is Script {
    uint256 private constant MARKET_BATCH_SIZE = 42;

    function run(
        address owner,
        address morpho,
        address[] memory swapRouters,
        address treasury,
        MarketConfig[] memory marketConfigs
    ) external returns (address) {
        vm.startBroadcast();

        // Deploy
        FlashLeverage flashLeverage = new FlashLeverage(
            owner,
            morpho,
            treasury
        );

        // Add swap routers
        for (uint256 i; i < swapRouters.length; ++i) {
            flashLeverage.setSwapRouter(swapRouters[i], true);
        }

        vm.stopBroadcast();

        // Add supported markets in batches to avoid exceeding block gas limit
        uint256 total = marketConfigs.length;
        for (uint256 start; start < total; start += MARKET_BATCH_SIZE) {
            uint256 end = start + MARKET_BATCH_SIZE;
            if (end > total) end = total;

            uint256 batchLen = end - start;
            MarketConfig[] memory batch = new MarketConfig[](batchLen);
            for (uint256 j; j < batchLen; ++j) {
                batch[j] = marketConfigs[start + j];
            }

            vm.startBroadcast();
            flashLeverage.addSupportedMarkets(batch);
            vm.stopBroadcast();
        }

        return address(flashLeverage);
    }
}
