// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";
import {SPIUSD} from "../src/core/SPIUSD/SPIUSD.sol";
import {PositionManager} from "../src/core/SPIUSD/PositionManager.sol";

contract DeploySPIUSD is Script {
    function run(
        address[] memory collateralTokens,
        address[] memory priceFeeds,
        address treasury
    ) external returns (address spiUsdAddress, address positionManagerAddress) {
        vm.startBroadcast();
        spiUsdAddress = address(new SPIUSD());
        positionManagerAddress = address(
            new PositionManager(address(spiUsdAddress), treasury)
        );

        // Adding supported collateral tokens
        PositionManager(positionManagerAddress).addSupportedCollateralToken(
            collateralTokens,
            priceFeeds
        );
        vm.stopBroadcast();
    }
}
