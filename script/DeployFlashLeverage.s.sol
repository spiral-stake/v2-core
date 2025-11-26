// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {FlashLeverage} from "../src/core/FlashLeverage/FlashLeverage.sol";

contract DeployFlashLeverage is Script {
    function run(
        address morpho,
        address swapRouter,
        address treasury,
        address[] memory collateralTokens,
        bytes32[] memory morphoMarketIds
    ) external returns (address flashLeverageAddress) {
        vm.startBroadcast();

        // Deploy
        FlashLeverage flashLeverage = new FlashLeverage(
            morpho,
            swapRouter,
            treasury
        );

        // Add supported collateral token
        for (uint256 i; i < collateralTokens.length; ++i) {
            flashLeverage.addSupportedCollateralToken(
                collateralTokens[i],
                morphoMarketIds[i]
            );
        }

        vm.stopBroadcast();

        return address(flashLeverage);
    }
}
