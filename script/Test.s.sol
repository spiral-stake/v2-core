// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/shared/mocks/MockV3Aggregator.sol";
import {ERC20Mock} from "../src/mocks/ERC20Mock.sol";
import {IERC20Mock} from "../src/interfaces/IERC20Mock.sol";
import {DeployStblUSD, PositionManager} from "../script/DeployStblUSD.s.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {BorrowSwapper} from "../src/routers/BorrowSwapper.sol";
import {LeverageWrapper} from "../src/routers/LeverageWrapper.sol";
import {DeployFlashLeverage, FlashLeverage} from "./DeployFlashLeverage.s.sol";

import {console} from "forge-std/console.sol";

contract Test is Script {
    function run() external {
        vm.startBroadcast();

        address frxUSD = 0x226E23821aCaa0c2c0ea567f8d59e343e145AaC2;
        address flashLeverage = 0x0B4D1aBabF658C753BeFA976160df440cCb12E5a;

        address[] memory collateralTokens = new address[](5);
        collateralTokens[0] = 0x1b922B45fd00D1d1E524538B45c963bC0C325189;
        collateralTokens[1] = 0x3d3aF2eCfaa71343B15aCf5D64d6fbBC2B22AD26;
        collateralTokens[2] = 0xb97e2Eaff562b702cB744352Da05646b6e9DD65F;
        collateralTokens[3] = 0xE4408cECD1eC5D8336b16998f010cf4f8497AB23;
        collateralTokens[4] = 0xb4ccD7d85bC96E6F260671E5f218B615a5cC62D9;

        address[] memory frxUSDCurvePools = new address[](5);
        frxUSDCurvePools[0] = 0x64529ee9b3C273EA1E56751e7ddd6d8FaA06B0E4;
        frxUSDCurvePools[1] = 0xAbF8A7ea0999dD6A5C4BD4e56B3270213503A2FC;
        frxUSDCurvePools[2] = 0xFEfB988F4dD830fc3b18089D534B0c911Cf2FB55;
        frxUSDCurvePools[3] = 0x11e596625076bC2782F1a09F20D344b39a8b1D3B;
        frxUSDCurvePools[4] = 0x03f45eA1fAEa9BA9f379286BaBf89de9fa0F660e;

        LeverageWrapper leverageWrapper = new LeverageWrapper(flashLeverage);
        leverageWrapper.addSupportedToken(
            frxUSD,
            collateralTokens,
            frxUSDCurvePools
        );

        vm.stopBroadcast();

        vm.startPrank(0x08675879B01177a9Bc80A7FC58c032cFA2Bb7742);

        uint256 amountFrxUSD = 100e18;
        IERC20(frxUSD).approve(address(leverageWrapper), amountFrxUSD);
        leverageWrapper.leverage(
            frxUSD,
            amountFrxUSD,
            collateralTokens[0],
            8e17
        );

        vm.stopPrank();
    }
}
