// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";
import {FlashLeverage} from "../src/core/FlashLeverage/FlashLeverage.sol";
import {MarketConfig} from "../src/core/structs/MarketConfig.sol";

contract DeployFlashLeverage is Script {
    function run(
        address morpho,
        address[] memory swapRouters,
        address treasury,
        MarketConfig[] memory marketConfigs
    ) external returns (address) {
        vm.startBroadcast();

        // Deploy
        FlashLeverage flashLeverage = new FlashLeverage(morpho, treasury);

        // Add supported collateral token
        flashLeverage.addSupportedMarkets(marketConfigs);

        // Add swap routers
        for (uint256 i; i < swapRouters.length; ++i) {
            flashLeverage.addSwapRouter(swapRouters[i]);
        }

        vm.stopBroadcast();
        return address(flashLeverage);
    }
}
