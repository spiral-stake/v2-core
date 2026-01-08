// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import {CollateralTokenConfig} from "../src/core/structs/CollateralTokenConfig.sol";

struct ChainConfig {
    address morpho;
    address pendleRouter;
    address[] swapRouters;
    address treasury;
    address WETH;
    address USDC;
}

/**
 * @title TokenConfig
 * @dev Configuration contract for collateral token settings
 * @notice Contains all collateral token configurations for the Flash Leverage system
 */
contract Config {
    function getChainConfig() internal view returns (ChainConfig memory chain) {
        // Commons
        chain.treasury = 0xeB90258b1F74a846F7941514C7c02Bb03EB249D5;
        chain.swapRouters = new address[](1);
        chain.swapRouters[0] = 0x6131B5fae19EA4f9D964eAc0408E4408b66337b5;

        if (block.chainid == 31337 || block.chainid == 1) {
            chain.morpho = 0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb;
            chain.pendleRouter = 0x888888888889758F76e7103c6CbF23ABbF58F946;
            chain.WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
            chain.USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        } else if (block.chainid == 137) {
            chain.morpho = 0x1bF0c2541F820E775182832f06c0B7Fc27A25f67;
            chain.pendleRouter = address(0);
            chain.WETH = 0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619;
            chain.USDC = 0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359;
        }
    }

    function getCollateralTokens()
        internal
        view
        returns (CollateralTokenConfig[] memory tokenConfigs)
    {
        if (block.chainid == 31337 || block.chainid == 1) {
            tokenConfigs = new CollateralTokenConfig[](3);

            /// STRICT NOTICE  ///
            /// Always put the PTs later ///

            // // wstETH
            // // WETH
            // tokenConfigs[0] = CollateralTokenConfig({
            //     collateralToken: 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0,
            //     morphoMarketId: 0xb8fc70e82bc5bb53e773626fcc6a23f7eefa036918d7ef216ecfb1950a94a85e,
            //     pendleMarket: address(0)
            // });

            // // stcUSD
            // // WETH
            // tokenConfigs[1] = CollateralTokenConfig({
            //     collateralToken: 0x88887bE419578051FF9F4eb6C858A951921D8888,
            //     morphoMarketId: 0xeb17955ea422baeddbfb0b8d8c9086c5be7a9cfdefb292119a102e981a30062e,
            //     pendleMarket: address(0)
            // });

            // PTs after this //

            // PT-snUSD
            // USDC

            tokenConfigs[0] = CollateralTokenConfig({
                collateralToken: 0x545A490f9ab534AdF409A2E682bc4098f49952e3,
                morphoMarketId: 0x802ec6e878dc9fe6905b8a0a18962dcca10440a87fa2242fbf4a0461c7b0c789,
                pendleMarket: 0x307c15f808914Df5a5DbE17E5608f84953fFa023
            });

            tokenConfigs[1] = CollateralTokenConfig({
                collateralToken: 0xC3c7E5E277d31CD24a3Ac4cC9af3B6770F30eA33,
                morphoMarketId: 0x03f715ef1ae508ab3e1faf4dffdbf2a077d1f0ad10c5aad42cf4438d5e3328af,
                pendleMarket: 0xCC781b043933c10a04409b22aaDa3a3D1A7f29D4
            });
            tokenConfigs[2] = CollateralTokenConfig({
                collateralToken: 0x54Bf2659B5CdFd86b75920e93C0844c0364F5166,
                morphoMarketId: 0x2a9a5c436719badcfadbad3ad8e8179a160ded758603eaa03a883f922a1790d3,
                pendleMarket: 0x6D8C4DE7071D5AeE27fc3a810764E62a4a00Ceb9
            });
        } else if (block.chainid == 137) {
            tokenConfigs = new CollateralTokenConfig[](2);

            // wstETH
            // WETH
            tokenConfigs[0] = CollateralTokenConfig({
                collateralToken: 0x03b54A6e9a984069379fae1a4fC4dBAE93B3bCCD,
                morphoMarketId: 0xb8ae474af3b91c8143303723618b31683b52e9c86566aa54c06f0bc27906bcae,
                pendleMarket: address(0)
            });

            // MaticX
            // WPOL
            tokenConfigs[1] = CollateralTokenConfig({
                collateralToken: 0xfa68FB4628DFF1028CFEc22b4162FCcd0d45efb6,
                morphoMarketId: 0xa932e0d8a9bf52d45b8feac2584c7738c12cf63ba6dff0e8f199e289fb5ca9bb,
                pendleMarket: address(0)
            });
        }
    }

    function getCollateralTokenWhales()
        internal
        pure
        returns (address[] memory tokenWhales)
    {
        tokenWhales = new address[](3);

        tokenWhales[0] = 0x8Cc5a546408C6cE3C9eeB99788F9EC3b8FA6b9F3; // PT-cUSD
        tokenWhales[1] = 0x8Cc5a546408C6cE3C9eeB99788F9EC3b8FA6b9F3; // PT-stcUSD
        tokenWhales[2] = 0x49E96E255bA418d08E66c35b588E2f2F3766E1d0; // PT-snUSD
    }
}
