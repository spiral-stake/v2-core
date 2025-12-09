// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {FlashLeverage} from "../src/core/FlashLeverage/FlashLeverage.sol";
import {CollateralTokenConfig} from "../src/core/structs/CollateralTokenConfig.sol";

contract DeployFlashLeverage is Script {
    function run(
        address morpho,
        address pendleRouter,
        address[] memory swapRouters,
        address treasury,
        CollateralTokenConfig[] memory collateralTokens
    ) external returns (address flashLeverageAddress) {
        vm.startBroadcast();

        // Deploy
        FlashLeverage flashLeverage = new FlashLeverage(
            morpho,
            pendleRouter,
            swapRouters,
            treasury
        );

        // Add supported collateral token
        for (uint256 i; i < collateralTokens.length; ++i) {
            flashLeverage.addSupportedCollateralTokens(collateralTokens);
        }

        vm.stopBroadcast();
        return address(flashLeverage);
    }
}
