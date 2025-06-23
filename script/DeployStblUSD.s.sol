// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";
import {StblUSD, IStblUSD} from "../src/core/borrow/StblUSD.sol";
import {PositionManager} from "../src/core/borrow/PositionManager.sol";

contract DeployStblUSD is Script {
    function run() external returns (address stblUSDAddress) {
        vm.startBroadcast();

        stblUSDAddress = address(new StblUSD());

        vm.stopBroadcast();
    }
}
