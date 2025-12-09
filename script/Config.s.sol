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

        chain.swapRouters = new address[](1);
        chain.swapRouters[0] = 0x6131B5fae19EA4f9D964eAc0408E4408b66337b5;
    }

    function getCollateralTokens()
        internal
        view
        returns (CollateralTokenConfig[] memory tokenConfigs)
    {
        if (block.chainid == 31337 || block.chainid == 1) {
            tokenConfigs = new CollateralTokenConfig[](4);

            /// STRICT NOTICE  ///
            /// Always put the PTs later ///

            // wstETH
            // USDC
            tokenConfigs[0] = CollateralTokenConfig({
                collateralToken: 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0,
                morphoMarketId: 0xb323495f7e4148be5643a4ea4a8221eef163e4bccfdedc2a6f4696baacbc86cc,
                pendleMarket: address(0)
            });

            // wstETH
            // WETH
            tokenConfigs[1] = CollateralTokenConfig({
                collateralToken: 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0,
                morphoMarketId: 0xb8fc70e82bc5bb53e773626fcc6a23f7eefa036918d7ef216ecfb1950a94a85e,
                pendleMarket: address(0)
            });

            // stcUSD
            // WETH
            tokenConfigs[2] = CollateralTokenConfig({
                collateralToken: 0x88887bE419578051FF9F4eb6C858A951921D8888,
                morphoMarketId: 0xeb17955ea422baeddbfb0b8d8c9086c5be7a9cfdefb292119a102e981a30062e,
                pendleMarket: address(0)
            });

            // PTs after this //

            // PT-stcUSD
            // USDC
            tokenConfigs[3] = CollateralTokenConfig({
                collateralToken: 0xC3c7E5E277d31CD24a3Ac4cC9af3B6770F30eA33,
                morphoMarketId: 0x03f715ef1ae508ab3e1faf4dffdbf2a077d1f0ad10c5aad42cf4438d5e3328af,
                pendleMarket: 0xCC781b043933c10a04409b22aaDa3a3D1A7f29D4
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

    function getTokenWhales()
        internal
        pure
        returns (address[] memory tokenWhales)
    {
        tokenWhales = new address[](10);

        tokenWhales[0] = 0xF087C34d81A552D2b82Fe67b8ac3e707a0aDc561; // PT-sUSDE
        tokenWhales[1] = 0x8c31AF1388666aD031c45f25B31017eAAD4C5239; // PT-USDe
        tokenWhales[2] = 0xfF43C5727FbFC31Cb96e605dFD7546eb8862064C; // PT-pUSDe
        tokenWhales[3] = 0x66a4327C7D280aC317A23145a6DEEF1460EE29aC; // PT-USR (bal 100)
        tokenWhales[4] = 0x5a407865411253E5A991d3e49E8Bc7A1FdBE82B0; // PT-rUSD (bal 9000)
        tokenWhales[5] = 0x68e7E72938db36a5CBbCa7b52c71DBBaaDfB8264; // PT-cUSD
        tokenWhales[6] = 0x1fDDD2218dEf78EE99bd2A5cBD8c5F263fbAe632; // PT-stcUSD
        tokenWhales[7] = 0xc3A1bab8fef2767db914b8c22d0617933a91E3b0; // PT-cUSDL
        tokenWhales[8] = 0x3c9Ea5C4Fec2A77E23Dd82539f4414266Fe8f757; // PT-cUSDO
        tokenWhales[9] = 0xf3aC4D503991Ed1aBa52B03F7cB4e7B4210AB92C; // PT-fxSave
    }
}
