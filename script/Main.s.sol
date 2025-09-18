// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

import {CollateralTokenConfig} from "../src/core/structs/CollateralTokenConfig.sol";
import {TokenConfigs} from "./TokenConfigs.sol";
import {DeployFlashLeverageCore} from "./DeployFlashLeverageCore.s.sol";
import {DeployFlashLeverage} from "./DeployFlashLeverage.s.sol";
import {WriteAddresses} from "./WriteAddresses.s.sol";

interface IWETH {
    function deposit() external payable;
}

contract Main is Script, WriteAddresses {
    address public morpho = 0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb;
    address public pendleRouter = 0x888888888889758F76e7103c6CbF23ABbF58F946;

    uint256 public liquidationBuffer = 25e15;
    uint256 public slippageBuffer = 1e16;
    address public treasury = 0x4d45d0079968F50630E2643E4090A551DCAecA68;

    address public WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    // Token configuration contract
    TokenConfigs public tokenConfigsContract;

    function setUp() external {
        if (block.chainid == 31337) {
            vm.startBroadcast();
            IWETH(WETH).deposit{value: 10 ether}();
            vm.stopBroadcast();
        }
    }

    function run()
        external
        returns (address flashLeverageCoreAddress, address flashLeverageAddress)
    {
        tokenConfigsContract = new TokenConfigs();

        CollateralTokenConfig[] memory tokenConfigs = tokenConfigsContract
            .getTokenConfigs();

        flashLeverageCoreAddress = _deployFlashLeverageCore(tokenConfigs);
        flashLeverageAddress = _deployFlashLeverage(
            flashLeverageCoreAddress,
            tokenConfigs
        );

        _writeAddresses(
            morpho,
            tokenConfigs,
            USDC,
            flashLeverageCoreAddress,
            flashLeverageAddress,
            "./addresses/"
        );
    }

    function _deployFlashLeverageCore(
        CollateralTokenConfig[] memory tokenConfigs
    ) private returns (address flashLeverageCoreAddress) {
        flashLeverageCoreAddress = new DeployFlashLeverageCore().run(
            morpho,
            pendleRouter,
            liquidationBuffer,
            slippageBuffer,
            tokenConfigs
        );
    }

    function _deployFlashLeverage(
        address flashLeverageCoreAddress,
        CollateralTokenConfig[] memory tokenConfigs
    ) private returns (address flashLeverageAddress) {
        flashLeverageAddress = new DeployFlashLeverage().run(
            flashLeverageCoreAddress,
            pendleRouter,
            treasury,
            tokenConfigs
        );
    }

    /**
     * @dev Returns all collateral token configurations
     * @return Array of CollateralTokenConfig structs
     */
    function getCollateralTokenConfigs()
        external
        view
        returns (CollateralTokenConfig[] memory)
    {
        return tokenConfigsContract.getTokenConfigs();
    }

    function getCollateralTokenWhales()
        external
        view
        returns (address[] memory)
    {
        return tokenConfigsContract.getTokenWhales();
    }
}
