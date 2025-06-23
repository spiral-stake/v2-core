// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/shared/mocks/MockV3Aggregator.sol";
import {ERC20Mock} from "../src/mocks/ERC20Mock.sol";

struct ChainConfig {
    uint256 id;
    bool isTestnet;
    bool isLocal;
    address[] collateralTokens;
    address[] priceFeeds;
    address frxUSD;
    address treasury;
    uint256 deployerKey;
}

contract HelperConfig is Script {
    uint256 public DEFAULT_ANVIL_PRIVATE_KEY =
        0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    function deployIfNeededAndGetConfig()
        external
        returns (ChainConfig memory chain)
    {
        chain.treasury = address(0x121);

        vm.startBroadcast();

        if (block.chainid == 31337) {
            chain.isLocal = true;
            chain.deployerKey = DEFAULT_ANVIL_PRIVATE_KEY;

            // Staked Stablecoins for collateral tokens
            chain.collateralTokens = new address[](5);

            chain.collateralTokens[0] = address(
                new ERC20Mock("PT-sUSDE-25SEP2025", "PT-sUSDE")
            );

            chain.collateralTokens[1] = address(
                new ERC20Mock("PT-slvlUSD-25SEP2025", "PT-slvlUSD")
            );

            chain.collateralTokens[2] = address(
                new ERC20Mock("PT-csUSDL-31JUL2025", "PT-csUSDL")
            );

            chain.collateralTokens[3] = address(
                new ERC20Mock("Staked frxUSD", "sfrxUSD")
            );
            chain.collateralTokens[4] = address(
                new ERC20Mock("Staked USDf", "sUSDf")
            );

            // Respective price feeds for the staked staked stables
            chain.priceFeeds = new address[](5);
            uint8 PRICE_FEED_DECIMALS = 8;

            int256 PTSUSDE_PRICE = 10095e4;
            chain.priceFeeds[0] = address(
                new MockV3Aggregator(PRICE_FEED_DECIMALS, PTSUSDE_PRICE)
            );

            int256 PTSLVLUSD_PRICE = 102e6;
            chain.priceFeeds[1] = address(
                new MockV3Aggregator(PRICE_FEED_DECIMALS, PTSLVLUSD_PRICE)
            );

            int256 PTCSUSDL_PRICE = 103e6;
            chain.priceFeeds[2] = address(
                new MockV3Aggregator(PRICE_FEED_DECIMALS, PTCSUSDL_PRICE)
            );

            int256 SFRXUSD_PRICE = 113e6;
            chain.priceFeeds[3] = address(
                new MockV3Aggregator(PRICE_FEED_DECIMALS, SFRXUSD_PRICE)
            );

            int256 SUSDF_PRICE = 105e6;
            chain.priceFeeds[4] = address(
                new MockV3Aggregator(PRICE_FEED_DECIMALS, SUSDF_PRICE)
            );

            // frxUSD for StblUSD/frxUSD pair
            chain.frxUSD = address(new ERC20Mock("frxUSD", "frxUSD"));

            vm.stopBroadcast();
        }
    }
}
