// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";
import {SPIUSD, ISPIUSD} from "../src/core/SPIUSD/SPIUSD.sol";
import {PositionManager} from "../src/core/SPIUSD/PositionManager.sol";

contract DeploySPIUSD is Script {
    function run() external returns (address spiUsdAddress) {
        vm.startBroadcast();

        spiUsdAddress = address(new SPIUSD());

        vm.stopBroadcast();
    }
}
