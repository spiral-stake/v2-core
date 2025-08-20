// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {Math} from "../src/core/libraries/Math.sol";
import {IMorpho, MarketParams, Id} from "@morpho/interfaces/IMorpho.sol";
import {Setup} from "./Setup.t.sol";
import {LeveragePosition} from "../src/core/structs/LeveragePosition.sol";
import {CollateralTokenConfig} from "../src/core/structs/CollateralTokenConfig.sol";

contract TestFlashLeverage is Test, Setup {
    using Math for uint256;
    address PT_SLVL_WHALE = 0x46a83dC1a264Bff133dB887023d2884167094837;

    function testLeverage() external {
        address user = PT_SLVL_WHALE;
        uint256 amountCollateral = 100e18;
        uint256 desiredLtv = 80e16;
        CollateralTokenConfig memory config = tokensConfig[0];
        MarketParams memory marketParams = morpho.idToMarketParams(
            Id.wrap(config.morphoMarketId)
        );
        bytes memory leverageCalldata = getLeverageCalldata(
            user,
            desiredLtv,
            marketParams.collateralToken,
            marketParams.loanToken,
            amountCollateral
        );

        vm.startPrank(user);
        IERC20(marketParams.collateralToken).approve(
            address(fl),
            amountCollateral
        );
        (bool success, ) = address(fl).call(leverageCalldata);
        vm.stopPrank();

        LeveragePosition memory userLeveragePosition = fl
            .getUserLeveragePosition(user, 0); // 1st position id is 0

        require(success == true, "Leverage Call Failed");
        assertEq(userLeveragePosition.amountCollateral, amountCollateral);
    }

    /////////////////////////
    // Public and External View Functions

    function testTreasuryAddress() external view {
        address expectedTreasury = treasury;
        address actualTreasury = fl.getTreasury();
        assertEq(actualTreasury, expectedTreasury);
    }
}
