// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";

import {DeployFlashLeverage} from "./DeployFlashLeverage.s.sol";
import {DeployFlashLeverageRouter} from "./DeployFlashLeverageRouter.sol";
import {WriteAddresses} from "./WriteAddresses.s.sol";
import {Config, ChainConfig} from "./Config.s.sol";
import {MarketConfig} from "../src/core/structs/MarketConfig.sol";

interface IWETH {
    function deposit() external payable;
}

contract Main is Script, WriteAddresses, Config {
    function run() external returns (address flashLeverage) {
        ChainConfig memory chain = getChainConfig();
        MarketConfig[] memory marketConfigs = getMarketConfigs();

        if (block.chainid == 31337) {
            vm.startBroadcast();
            IWETH(chain.WETH).deposit{value: 10 ether}();
            vm.stopBroadcast();
        }

        flashLeverage = _deployFlashLeverage(chain, marketConfigs);
        address flashLeverageRouter = _deployFlashLeverageRouter(
            chain.morpho,
            flashLeverage
        );

        _writeAddresses(
            chain.morpho,
            marketConfigs,
            flashLeverage,
            flashLeverageRouter,
            "./addresses/"
        );
    }

    function _deployFlashLeverage(
        ChainConfig memory chain,
        MarketConfig[] memory marketConfigs
    ) private returns (address flashLeverage) {
        flashLeverage = new DeployFlashLeverage().run(
            chain.morpho,
            chain.swapRouters,
            chain.treasury,
            marketConfigs
        );
    }

    function _deployFlashLeverageRouter(
        address morpho,
        address flashLeverage
    ) private returns (address flashLeverageRouter) {
        flashLeverageRouter = new DeployFlashLeverageRouter().run(
            morpho,
            flashLeverage
        );
    }
}
