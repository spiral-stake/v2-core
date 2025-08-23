// // SPDX-License-Identifier: GPL-3.0-or-later
// pragma solidity 0.8.30;

// import {Test} from "forge-std/Test.sol";
// import {console} from "forge-std/console.sol";

// import {Math} from "../src/core/libraries/Math.sol";
// import {IMorpho, MarketParams, Id} from "@morpho/interfaces/IMorpho.sol";
// import {Setup} from "./Setup.t.sol";
// import {LeveragePosition} from "../src/core/structs/LeveragePosition.sol";
// import {CollateralTokenConfig} from "../src/core/structs/CollateralTokenConfig.sol";
// import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
// import {FLError} from "../src/core/libraries/Error.sol";

// contract TestFlashLeverage is Test, Setup {
//     using Math for uint256;

//     /////////////////////////
//     // Default Values

//     address USER = 0x925109e0AfFe306c31B55d8181e766D53aF7A778; // PT-USDE-WHALE
//     uint256 DESIRED_LTV = 80e16;
//     address COLLATERAL_TOKEN = 0xBC6736d346a5eBC0dEbc997397912CD9b8FAe10a; // PT-USDE
//     address LOAN_TOKEN = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // USDC
//     uint256 AMOUNT_COLLATERAL = 100e18;

//     /////////////////////////
//     // Modifiers

//     modifier leverage() {
//         bytes memory leverageCallData = getLeverageCalldata(
//             USER,
//             DESIRED_LTV,
//             COLLATERAL_TOKEN,
//             LOAN_TOKEN,
//             AMOUNT_COLLATERAL
//         );

//         vm.startPrank(USER);

//         IERC20(COLLATERAL_TOKEN).approve(address(fl), AMOUNT_COLLATERAL);
//         (bool success, ) = address(fl).call(leverageCallData);
//         require(success == true, "Leverage Call Failed");

//         vm.stopPrank();
//         _;
//     }

//     /////////////////////////
//     // External Functions

//     function testLeverage() external leverage {
//         LeveragePosition memory leveragePosition = fl.getUserLeveragePosition(
//             USER,
//             0
//         );
//         assertEq(leveragePosition.amountCollateral, AMOUNT_COLLATERAL);
//     }

//     /////////////////////////
//     // Public and External View Functions

//     function testPendleRouterAddress() external view {
//         address expectedPendleRouter = pendleRouter;
//         address actualPendleRouter = address(fl.i_pendleRouter());
//         assertEq(actualPendleRouter, expectedPendleRouter);
//     }

//     function testFlashLeverageCoreAddress() external view {
//         address expectedFlashLeverage = address(flc);
//         address actualFlashLeverageCore = address(fl.i_flashLeverageCore());
//         assertEq(actualFlashLeverageCore, expectedFlashLeverage);
//     }

//     function testTreasuryAddress() external view {
//         address expectedTreasury = treasury;
//         address actualTreasury = fl.getTreasury();
//         assertEq(actualTreasury, expectedTreasury);
//     }

//     function testIsSupportedCollateralToken() external {
//         for (uint256 i; i < tokensConfig.length; ++i) {
//             address collateralToken = tokensConfig[i].collateralToken;
//             assertTrue(fl.isSupportedCollateralToken(collateralToken));
//         }

//         // For Unsupported Collateral Token
//         address unsupportedCollateralToken = makeAddr("randomAddress");
//         assertFalse(fl.isSupportedCollateralToken(unsupportedCollateralToken));
//     }

//     /////////////////////////
//     // Utils

//     function makeUnleverageCall(
//         address user,
//         uint256 positionId,
//         uint256 desiredLtv,
//         address collateralToken,
//         address loanToken,
//         uint256 amountCollateral
//     ) internal {
//         bytes memory leverageCalldata = getLeverageCalldata(
//             user,
//             desiredLtv,
//             collateralToken,
//             loanToken,
//             amountCollateral
//         );

//         vm.prank(user);
//         IERC20(collateralToken).approve(address(fl), amountCollateral);

//         (bool success, ) = address(fl).call(leverageCalldata);
//         require(success == true, "Leverage Call Failed");
//     }
// }
