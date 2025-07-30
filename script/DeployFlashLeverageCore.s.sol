// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";
import {FlashLeverageCore} from "../src/core/leverage/FlashLeverageCore.sol";
import {CollateralTokenConfig} from "../src/core/structs/CollateralTokenConfig.sol";

contract DeployFlashLeverageCore is Script {
    function run(
        address morpho,
        address pendleRouter,
        CollateralTokenConfig[] memory configs
    ) external returns (address flashLeverageAddress) {
        vm.startBroadcast();

        // Deploy
        FlashLeverageCore flashLeverageCore = new FlashLeverageCore(
            morpho,
            pendleRouter
        );

        // Add supported collateral tokens
        flashLeverageCore.addSupportedCollateralTokens(configs);

        vm.stopBroadcast();

        return address(flashLeverageCore);
    }
}
