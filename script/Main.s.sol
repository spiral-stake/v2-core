// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

import {DeployFlashLeverage} from "./DeployFlashLeverage.s.sol";
import {DeployFlashLeverageRouter} from "./DeployFlashLeverageRouter.sol";
import {WriteAddresses} from "./WriteAddresses.s.sol";
import {Config, ChainConfig, CollateralTokenConfig} from "./Config.s.sol";

interface IWETH {
    function deposit() external payable;
}

contract Main is Script, WriteAddresses, Config {
    function run() external returns (address flashLeverage) {
        ChainConfig memory chain = getChainConfig();
        CollateralTokenConfig[] memory collateralTokens = getCollateralTokens();

        if (block.chainid == 31337) {
            vm.startBroadcast();
            IWETH(chain.WETH).deposit{value: 10 ether}();
            vm.stopBroadcast();
        }

        flashLeverage = _deployFlashLeverage(chain, collateralTokens);
        address flashLeverageRouter = _deployFlashLeverageRouter(flashLeverage);

        _writeAddresses(
            chain.morpho,
            collateralTokens,
            flashLeverage,
            flashLeverageRouter,
            "./addresses/"
        );
    }

    function _deployFlashLeverage(
        ChainConfig memory chain,
        CollateralTokenConfig[] memory collateralTokenConfig
    ) private returns (address flashLeverage) {
        flashLeverage = new DeployFlashLeverage().run(
            chain.morpho,
            chain.swapRouters,
            chain.treasury,
            collateralTokenConfig
        );
    }

    function _deployFlashLeverageRouter(
        address flashLeverage
    ) private returns (address flashLeverageRouter) {
        flashLeverageRouter = new DeployFlashLeverageRouter().run(
            flashLeverage
        );
    }
}
