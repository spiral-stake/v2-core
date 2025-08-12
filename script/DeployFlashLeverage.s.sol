// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";
import {IFlashLeverageCore} from "../src/interfaces/IFlashLeverageCore.sol";
import {FlashLeverage} from "../src/core/leverage/FlashLeverage.sol";
import {CollateralTokenConfig} from "../src/core/structs/CollateralTokenConfig.sol";

contract DeployFlashLeverage is Script {
    function run(
        address flashLeverageCore,
        address pendleRouter,
        address treasury,
        CollateralTokenConfig[] memory tokensConfig
    ) external returns (address flashLeverageAddress) {
        vm.startBroadcast();

        // Deploy
        FlashLeverage flashLeverage = new FlashLeverage(
            flashLeverageCore,
            pendleRouter,
            treasury
        );

        // Set as Manager in FlashLeverageCore
        IFlashLeverageCore(flashLeverageCore).setManager(
            address(flashLeverage),
            true
        );

        // Add supported collateral tokens

        flashLeverage.addSupportedCollateralTokens(tokensConfig);

        vm.stopBroadcast();

        return address(flashLeverage);
    }
}
