// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";
import {HelperConfig, ChainConfig} from "./HelperConfig.s.sol";
import {IERC20Mock} from "../src/interfaces/IERC20Mock.sol";
import {FlashLeverage} from "../src/core/leverage/FlashLeverage.sol";
import {DeployStblUSD, PositionManager} from "../script/DeployStblUSD.s.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {CollateralTokenConfig} from "../src/core/structs/CollateralTokenConfig.sol";

contract DeployFlashLeverage is Script {
    function run(
        address morpho,
        address pendleRouter,
        address oracleRouter,
        CollateralTokenConfig[] memory configs
    ) external returns (address flashLeverageAddress) {
        vm.startBroadcast();

        flashLeverageAddress = address(
            new FlashLeverage(morpho, pendleRouter, oracleRouter)
        );

        FlashLeverage(flashLeverageAddress).addSupportedCollateralTokens(
            configs
        );

        vm.stopBroadcast();
    }
}

// address positionManager = 0x3fCb2803A9Dbb57acBB87fD07c96A859C4a60CEa;
// address treasury = makeAddr("treasury");

// address[] memory collateralTokens = new address[](5);
// collateralTokens[0] = 0x1b922B45fd00D1d1E524538B45c963bC0C325189;
// collateralTokens[1] = 0x3d3aF2eCfaa71343B15aCf5D64d6fbBC2B22AD26;
// collateralTokens[2] = 0xb97e2Eaff562b702cB744352Da05646b6e9DD65F;
// collateralTokens[3] = 0xE4408cECD1eC5D8336b16998f010cf4f8497AB23;
// collateralTokens[4] = 0xb4ccD7d85bC96E6F260671E5f218B615a5cC62D9;

// address[] memory curvePools = new address[](5);
// curvePools[0] = 0x157fC2f261C968e2e36943F2A5d42518874C94B7;
// curvePools[1] = 0x3B6ac9C01C4D1Ca249004247D2D63b5dCC50A8Eb;
// curvePools[2] = 0x9949a9Bc4FE274B221b24058F339e7A50897Dfff;
// curvePools[3] = 0x9666b2184D3650521d3909cB939564a5B62696B8;
// curvePools[4] = 0x8d94994Ec3C5cCb3dF7604bEbFeDace12A85FBEF;

// FlashLeverage flashLeverage = FlashLeverage(
//     new FlashLeverage(positionManager, treasury)
// );

// flashLeverage.addSupportedCollateralTokens(
//     collateralTokens,
//     curvePools
// );
