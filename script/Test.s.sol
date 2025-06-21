// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";
import {DeployFlashLeverage, FlashLeverage} from "./DeployFlashLeverage.s.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/shared/mocks/MockV3Aggregator.sol";
import {ERC20Mock} from "../src/mocks/ERC20Mock.sol";
import {DeploySPIUSD, PositionManager} from "../script/DeploySPIUSD.s.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

import {console} from "forge-std/console.sol";

contract Test is Script {
    function run() external {
        vm.startBroadcast();

        address[] memory collateralTokens = new address[](3);
        collateralTokens[0] = 0x1b922B45fd00D1d1E524538B45c963bC0C325189;
        collateralTokens[1] = 0x3d3aF2eCfaa71343B15aCf5D64d6fbBC2B22AD26;
        collateralTokens[2] = 0xb97e2Eaff562b702cB744352Da05646b6e9DD65F;

        address[] memory curvePools = new address[](3);
        curvePools[0] = 0xa84850336d604140D4f6AaF1DFCB2bFe900f89C9;
        curvePools[1] = 0xe437B0164D203dcb963ee41a3E686D32884Ee298;
        curvePools[2] = 0x90E9B8BF745C387c7DFAd2e3E23c338B4cA1121f;

        FlashLeverage(0x068bF5704cE3b666daa324d33472C5687b10f98d)
            .addSupportedCollateralTokens(collateralTokens, curvePools);
        vm.stopBroadcast();
    }
}
