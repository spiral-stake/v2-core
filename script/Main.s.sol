// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

import {DeployFlashLeverage} from "./DeployFlashLeverage.s.sol";
import {CollateralTokenConfig} from "./CollateralTokenConfig.s.sol";
import {WriteAddresses} from "./WriteAddresses.s.sol";

interface IWETH {
    function deposit() external payable;
}

contract Main is Script, WriteAddresses {
    address public morpho = 0x1bF0c2541F820E775182832f06c0B7Fc27A25f67;
    address public swapRouter = 0x6131B5fae19EA4f9D964eAc0408E4408b66337b5;

    // Production
    address public treasury = 0xeB90258b1F74a846F7941514C7c02Bb03EB249D5;
    address public WETH = 0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619;

    // Token configuration contract
    CollateralTokenConfig public collateralTokenConfig;

    function setUp() external {
        if (block.chainid == 31337) {
            vm.startBroadcast();
            IWETH(WETH).deposit{value: 10 ether}();
            vm.stopBroadcast();
        }
    }

    function run() external returns (address flashLeverageAddress) {
        collateralTokenConfig = new CollateralTokenConfig();

        (
            address[] memory collateralTokens,
            bytes32[] memory morphoMarketIds
        ) = collateralTokenConfig.getTokenConfigs();

        flashLeverageAddress = _deployFlashLeverage(
            collateralTokens,
            morphoMarketIds
        );

        _writeAddresses(
            morpho,
            collateralTokens,
            morphoMarketIds,
            WETH,
            flashLeverageAddress,
            "./addresses/"
        );
    }

    function _deployFlashLeverage(
        address[] memory collateralTokens,
        bytes32[] memory morphoMarketIds
    ) private returns (address flashLeverageAddress) {
        flashLeverageAddress = new DeployFlashLeverage().run(
            morpho,
            swapRouter,
            treasury,
            collateralTokens,
            morphoMarketIds
        );
    }
}
