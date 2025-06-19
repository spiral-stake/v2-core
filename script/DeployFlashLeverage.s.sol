// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";
import {HelperConfig, ChainConfig} from "./HelperConfig.s.sol";
import {IERC20Mock} from "../src/interfaces/IERC20Mock.sol";
import {FlashLeverage} from "../src/core/leverage/FlashLeverage.sol";
import {DeploySPIUSD, PositionManager} from "../script/DeploySPIUSD.s.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

contract DeployFlashLeverage is Script {
    function run(
        address positionManager,
        address[] memory collateralTokens,
        address[] memory curvePools,
        address treasury
    ) external returns (address flashLeverageAddress) {
        flashLeverageAddress = address(
            new FlashLeverage(positionManager, treasury)
        );

        FlashLeverage(flashLeverageAddress).addSupportedCollateralTokens(
            collateralTokens,
            curvePools
        );
    }
}

// vm.startBroadcast();

// address positionManager = 0x5f9ed0e41672e0833A2897DA457052CE42EACdC4;
// address treasury = makeAddr("treasury");

// address[] memory collateralTokens = new address[](3);
// collateralTokens[0] = 0xE4408cECD1eC5D8336b16998f010cf4f8497AB23;
// collateralTokens[1] = 0x26b8fAb1a8179822a3D8df35A063f38913904614;
// collateralTokens[2] = 0xb4ccD7d85bC96E6F260671E5f218B615a5cC62D9;

// address[] memory curvePools = new address[](3);
// curvePools[0] = 0x94e275Ee99D60ad327b92C34cB895E80bE625f95;
// curvePools[1] = 0x47F96c391E87461f7281CCa60dcf522d6b88604e;
// curvePools[2] = 0xb7b6143fEaa3499293c39631A98a445F0Cb19a31;

// (new DeployFlashLeverage()).run(
//     positionManager,
//     collateralTokens,
//     curvePools,
//     treasury
// );

// vm.stopBroadcast();
