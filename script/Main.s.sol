// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

import {CollateralTokenConfig} from "../src/core/structs/CollateralTokenConfig.sol";
import {DeployFlashLeverageCore} from "./DeployFlashLeverageCore.s.sol";
import {DeployFlashLeverage} from "./DeployFlashLeverage.s.sol";
import {WriteAddresses} from "./WriteAddresses.s.sol";

interface IWETH {
    function deposit() external payable;
}

contract Main is Script, WriteAddresses {
    address public morpho = 0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb;
    address public pendleRouter = 0x888888888889758F76e7103c6CbF23ABbF58F946;
    CollateralTokenConfig[] tokensConfig;
    uint256 public liquidationBuffer = 25e15;
    uint256 public slippageBuffer = 1e16;
    address public treasury = 0x4d45d0079968F50630E2643E4090A551DCAecA68;

    address public WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    function setUp() external {
        if (block.chainid == 31337) {
            vm.startBroadcast();
            IWETH(WETH).deposit{value: 10 ether}();
            vm.stopBroadcast();
        }
    }

    function _initializeConfig() private {
        tokensConfig = new CollateralTokenConfig[](5);

        // PT-USDe
        tokensConfig[0] = CollateralTokenConfig({
            collateralToken: 0xBC6736d346a5eBC0dEbc997397912CD9b8FAe10a,
            morphoMarketId: 0x7a5d67805cb78fad2596899e0c83719ba89df353b931582eb7d3041fd5a06dc8,
            pendleMarket: 0x6d98a2b6CDbF44939362a3E99793339Ba2016aF4
        });

        // PT-cUSDO
        tokensConfig[1] = CollateralTokenConfig({
            collateralToken: 0xB10DA2F9147f9cf2B8826877Cd0c95c18A0f42dc,
            morphoMarketId: 0x8a71a66ac828c2b6d4f8accce5859aba0822b502f3833bec4aff09479affffdb,
            pendleMarket: 0x3F53eb4c57c7E7118BE8566bCd503EA502639581
        });

        // PT-slvlUSD
        tokensConfig[2] = CollateralTokenConfig({
            collateralToken: 0x2CA5f2C4300450D53214B00546795c1c07B89acB,
            morphoMarketId: 0x4005ba6eb7d2221fe58102bd320aa6d83c47b212771bc950ab71c5074d9ab0ec,
            pendleMarket: 0xC88FF954d42d3e11D43B62523B3357847C29377c
        });

        // PT-wstUSR
        tokensConfig[3] = CollateralTokenConfig({
            collateralToken: 0x23E60d1488525bf4685f53b3aa8E676c30321066,
            morphoMarketId: 0xeec6c7e2ddb7578f2a7d86fc11cf9da005df34452ad9b9189c51266216f5d71b,
            pendleMarket: 0x09fA04Aac9c6d1c6131352EE950CD67ecC6d4fB9
        });

        // PT-USDS-SPK
        tokensConfig[4] = CollateralTokenConfig({
            collateralToken: 0xC347584b415715B1b66774B2899Fef2FD3b56d6e,
            morphoMarketId: 0x366bc0aa9aa70a1f075096e825e9b1c7221878a90edd52081d2af5cfca3beb89,
            pendleMarket: 0xff43e751f2f07BbF84Da1fc1fa12cE116bF447E5
        });
    }

    function run()
        external
        returns (address flashLeverageCoreAddress, address flashLeverageAddress)
    {
        _initializeConfig();
        flashLeverageCoreAddress = _deployFlashLeverageCore();
        flashLeverageAddress = _deployFlashLeverage(flashLeverageCoreAddress);

        _writeAddresses(
            morpho,
            tokensConfig,
            USDC,
            flashLeverageCoreAddress,
            flashLeverageAddress,
            "./addresses/"
        );
    }

    function _deployFlashLeverageCore()
        private
        returns (address flashLeverageCoreAddress)
    {
        flashLeverageCoreAddress = new DeployFlashLeverageCore().run(
            morpho,
            pendleRouter,
            liquidationBuffer,
            slippageBuffer,
            tokensConfig
        );
    }

    function _deployFlashLeverage(
        address flashLeverageCoreAddress
    ) private returns (address flashLeverageAddress) {
        flashLeverageAddress = new DeployFlashLeverage().run(
            flashLeverageCoreAddress,
            pendleRouter,
            treasury,
            tokensConfig
        );
    }

    function getCollateralTokensConfig()
        external
        view
        returns (CollateralTokenConfig[] memory)
    {
        return tokensConfig;
    }
}
