// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

import {DeployFlashLeverage} from "./DeployFlashLeverage.s.sol";
import {WriteAddresses} from "./WriteAddresses.s.sol";
import {Config, ChainConfig, CollateralTokenConfig} from "./Config.s.sol";

interface IWETH {
    function deposit() external payable;
}

contract Main is Script, WriteAddresses, Config {
    ChainConfig private chain;
    CollateralTokenConfig[] private collateralTokens;

    function setUp() external {
        chain = getChainConfig();
        collateralTokens = getCollateralTokens();

        if (block.chainid == 31337) {
            vm.startBroadcast();
            IWETH(chain.WETH).deposit{value: 10 ether}();
            vm.stopBroadcast();
        }
    }

    function run() external returns (address flashLeverageAddress) {
        flashLeverageAddress = _deployFlashLeverage(collateralTokens);

        _writeAddresses(
            chain.morpho,
            collateralTokens,
            chain.USDC,
            flashLeverageAddress,
            "./addresses/"
        );
    }

    function _deployFlashLeverage(
        CollateralTokenConfig[] memory collateralTokenConfig
    ) private returns (address flashLeverageAddress) {
        flashLeverageAddress = new DeployFlashLeverage().run(
            chain.morpho,
            chain.pendleRouter,
            chain.swapRouters,
            chain.treasury,
            collateralTokenConfig
        );
    }
}
