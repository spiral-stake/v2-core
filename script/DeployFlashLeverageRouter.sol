// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";
import {FlashLeverageRouter} from "../src/router/FlashLeverageRouter.sol";
import {FlashLeverage} from "../src/core/FlashLeverage/FlashLeverage.sol";

contract DeployFlashLeverageRouter is Script {
    function run(
        address morpho,
        address flashLeverage
    ) external returns (address flashLeverageRouter) {
        vm.startBroadcast();

        // Deploy
        flashLeverageRouter = address(
            new FlashLeverageRouter(morpho, flashLeverage)
        );

        // Set router as operator
        FlashLeverage(flashLeverage).setApprovedOperator(
            flashLeverageRouter,
            true
        );

        vm.stopBroadcast();
    }
}
