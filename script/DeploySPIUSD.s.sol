// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";
import {SPIUSD} from "../src/core/SPIUSD/SPIUSD.sol";
import {VaultManager} from "../src/core/SPIUSD/VaultManager.sol";

contract DeploySPIUSD is Script {
    function run(
        uint256 deployerKey,
        address[] memory collateralTokens,
        address[] memory priceFeeds,
        address treasury
    ) external returns (SPIUSD spiUsd, VaultManager vaultManager) {
        vm.broadcast(deployerKey);
        spiUsd = new SPIUSD();
        vaultManager = new VaultManager(address(spiUsd), treasury);

        // Adding supported collateral tokens
        vaultManager.setCollateralTokenSupport(collateralTokens, priceFeeds);
    }
}
