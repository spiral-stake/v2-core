// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {FlashLeverageRouter} from "../src/router/FlashLeverageRouter.sol";

contract DeployFlashLeverageRouter is Script {
    function run(
        address flashLeverage
    ) external returns (address flashLeverageRouter) {
        vm.startBroadcast();

        // Deploy
        flashLeverageRouter = address(new FlashLeverageRouter(flashLeverage));

        vm.stopBroadcast();
    }
}
