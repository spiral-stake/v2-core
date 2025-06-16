// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";
import {HelperConfig, ChainConfig} from "./HelperConfig.s.sol";
import {DeploySPIUSD} from "./DeploySPIUSD.s.sol";
import {WriteAddressesToJson} from "./WriteAddresses.s.sol";

contract Main is Script {
    function run() external {
        HelperConfig helperConfig = new HelperConfig();
        ChainConfig memory chain = helperConfig.deployIfNeededAndGetConfig();

        // Deploying SPIUSD
        (address spiUsdAddress, address positionManagerAddress) = (
            new DeploySPIUSD()
        ).run(chain.collateralTokens, chain.priceFeeds, chain.treasury);

        (new WriteAddressesToJson())._writeAddressesToJson(
            spiUsdAddress,
            positionManagerAddress,
            chain.collateralTokens
        );
    }
}
