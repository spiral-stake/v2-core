// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import {CollateralTokenConfig} from "../src/core/structs/CollateralTokenConfig.sol";

struct ChainConfig {
    address morpho;
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
        chain.swapRouters = new address[](2);
        chain.swapRouters[0] = 0x6131B5fae19EA4f9D964eAc0408E4408b66337b5; // Kyberswap Router

        if (block.chainid == 31337 || block.chainid == 1) {
            chain.morpho = 0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb;
            chain.WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
            chain.USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
            chain.swapRouters[1] = 0x888888888889758F76e7103c6CbF23ABbF58F946; // Pendle Swap Router
        } else if (block.chainid == 137) {
            chain.morpho = 0x1bF0c2541F820E775182832f06c0B7Fc27A25f67;
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
            tokenConfigs = new CollateralTokenConfig[](4);

            // wstETH/WETH - staked ETH
            tokenConfigs[0] = CollateralTokenConfig({
                collateralToken: 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0,
                morphoMarketId: 0xb8fc70e82bc5bb53e773626fcc6a23f7eefa036918d7ef216ecfb1950a94a85e
            });

            // siUSD/USDC - staked stablecoin
            tokenConfigs[1] = CollateralTokenConfig({
                collateralToken: 0xDBDC1Ef57537E34680B898E1FEBD3D68c7389bCB,
                morphoMarketId: 0xbbf7ce1b40d32d3e3048f5cf27eeaa6de8cb27b80194690aab191a63381d8c99
            });

            // PT-stcUSD - Stablecoin PT from pendle
            tokenConfigs[2] = CollateralTokenConfig({
                collateralToken: 0xC3c7E5E277d31CD24a3Ac4cC9af3B6770F30eA33,
                morphoMarketId: 0x03f715ef1ae508ab3e1faf4dffdbf2a077d1f0ad10c5aad42cf4438d5e3328af
            });

            // PT-reUSD - Stablecoin PT from pendle (with 6 decimals)
            tokenConfigs[3] = CollateralTokenConfig({
                collateralToken: 0x3EAA0F0f0A5d3D595ae4e4b0D27f439d01c3E7b2,
                morphoMarketId: 0x9bc98c2f20ac58287ef2c860eea53a2fdc27c17a7817ff1206c0b7840cc7cd79
            });
        } else if (block.chainid == 137) {
            tokenConfigs = new CollateralTokenConfig[](2);
            // wstETH/WETH
            tokenConfigs[0] = CollateralTokenConfig({
                collateralToken: 0x03b54A6e9a984069379fae1a4fC4dBAE93B3bCCD,
                morphoMarketId: 0xb8ae474af3b91c8143303723618b31683b52e9c86566aa54c06f0bc27906bcae
            });

            // MaticX/WPOL
            tokenConfigs[1] = CollateralTokenConfig({
                collateralToken: 0xfa68FB4628DFF1028CFEc22b4162FCcd0d45efb6,
                morphoMarketId: 0xa932e0d8a9bf52d45b8feac2584c7738c12cf63ba6dff0e8f199e289fb5ca9bb
            });
        }
    }

    function getCollateralTokenWhales()
        internal
        view
        returns (address[] memory tokenWhales)
    {
        if (block.chainid == 31337 || block.chainid == 1) {
            tokenWhales = new address[](4);
            tokenWhales[0] = 0x5313b39bf226ced2332C81eB97BB28c6fD50d1a3; // wstETH
            tokenWhales[1] = 0x289C204B35859bFb924B9C0759A4FE80f610671c; // siUSD
            tokenWhales[2] = 0x8Cc5a546408C6cE3C9eeB99788F9EC3b8FA6b9F3; // PT-reUSD
            tokenWhales[3] = 0xa427DEf3f920F718A89e5ab473c79C065ab10Ef4; // PT-reUSD
        } else if (block.chainid == 137) {
            tokenWhales = new address[](2);
            tokenWhales[0] = 0xf81bF14Ae234D1B1F13414Fd63Ca064D16b79ad4; // wstETH
            tokenWhales[1] = 0x03ec2cE18792cEff5F835711B294D568E8Cb078a; // MaticX
        }
    }
}
