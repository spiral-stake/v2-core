// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";
import {IWETH} from "../src/interfaces/IWETH.sol";
import {CollateralTokenConfig} from "../src/core/structs/CollateralTokenConfig.sol";
import {DeployFlashLeverageCore} from "./DeployFlashLeverageCore.s.sol";
import {DeployFlashLeverage} from "./DeployFlashLeverage.s.sol";

import {console} from "forge-std/console.sol";

contract Main is Script {
    address morpho = 0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb;
    address pendleRouter = 0x888888888889758F76e7103c6CbF23ABbF58F946;
    address WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    function setUp() external {
        vm.startBroadcast();
        if (block.chainid == 31337) {
            IWETH(WETH).deposit{value: 10 ether}();
        }
        vm.stopBroadcast();
    }

    function run() external {
        CollateralTokenConfig[] memory configs = new CollateralTokenConfig[](5);

        // PT-slvlUSD
        configs[0] = CollateralTokenConfig({
            collateralToken: 0x2CA5f2C4300450D53214B00546795c1c07B89acB,
            morphoMarketId: 0x8ebcaf72c7cd75e8c621ec77ec343b3152c48908c4a6e217da82fe6af23c1928,
            pendleMarket: 0xC88FF954d42d3e11D43B62523B3357847C29377c
        });

        // PT-wstUSR
        configs[1] = CollateralTokenConfig({
            collateralToken: 0x23E60d1488525bf4685f53b3aa8E676c30321066,
            morphoMarketId: 0xeec6c7e2ddb7578f2a7d86fc11cf9da005df34452ad9b9189c51266216f5d71b,
            pendleMarket: 0x09fA04Aac9c6d1c6131352EE950CD67ecC6d4fB9
        });

        // PT-USDS
        configs[2] = CollateralTokenConfig({
            collateralToken: 0xFfEc096c087C13Cc268497B89A613cACE4DF9A48,
            morphoMarketId: 0xa458018cf1a6e77ebbcc40ba5776ac7990e523b7cc5d0c1e740a4bbc13190d8f,
            pendleMarket: 0xdacE1121e10500e9e29d071F01593fD76B000f08
        });

        // PT-cUSDO
        configs[3] = CollateralTokenConfig({
            collateralToken: 0xB10DA2F9147f9cf2B8826877Cd0c95c18A0f42dc,
            morphoMarketId: 0x8a71a66ac828c2b6d4f8accce5859aba0822b502f3833bec4aff09479affffdb,
            pendleMarket: 0x3F53eb4c57c7E7118BE8566bCd503EA502639581
        });

        // PT-USDe
        configs[4] = CollateralTokenConfig({
            collateralToken: 0xBC6736d346a5eBC0dEbc997397912CD9b8FAe10a,
            morphoMarketId: 0x3462a9442ec1aa46fc38bf91472b593b8fb86bf18eac47ebf82493dc4bed5b1b,
            pendleMarket: 0x6d98a2b6CDbF44939362a3E99793339Ba2016aF4
        });

        address flashLeverageCoreAddress = new DeployFlashLeverageCore().run(
            morpho,
            pendleRouter,
            configs
        );

        address flashLeverageAddress = new DeployFlashLeverage().run(
            flashLeverageCoreAddress,
            pendleRouter,
            configs
        );

        console.log(flashLeverageCoreAddress);
        console.log(flashLeverageAddress);
    }
}
