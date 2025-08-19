// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {IFlashLeverageCore, FLCError, IOracle, Math, IERC20Metadata} from "../src/core/leverage/FlashLeverageCore.sol";
import {Math} from "../src/core/libraries/Math.sol";
import {IMorpho, MarketParams, Id} from "@morpho/interfaces/IMorpho.sol";
import {Setup} from "./Setup.t.sol";
import {CollateralTokenConfig} from "../src/core/structs/CollateralTokenConfig.sol";

contract TestFlashLeverageCore is Test, Setup {
    using Math for uint256;

    /////////////////////////
    // Public and External View Functions

    function testMorphoAndPendleRouterAddresses() external view {
        assertEq(flc.i_morpho(), address(morpho));
        assertEq(flc.i_pendleRouter(), pendleRouter);
    }

    function testLiquidationAndSlippageBuffers() external view {
        assertEq(flc.i_liquidationBuffer(), liquidationBuffer);
        assertEq(flc.i_slippageBuffer(), slippageBuffer);
    }

    function testRenounceOwnershipReverts() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                FLCError.FlashLeverageCore__RenounceOwnershipDisabled.selector
            )
        );
        flc.renounceOwnership();
    }

    function testGetLiqLtv() external view {
        CollateralTokenConfig memory config = tokensConfig[0];
        MarketParams memory marketParams = morpho.idToMarketParams(
            Id.wrap(config.morphoMarketId)
        );

        uint256 expectedLiqLtv = marketParams.lltv;

        assertEq(
            flc.getLiqLtv(config.collateralToken, marketParams.loanToken),
            expectedLiqLtv
        );
    }

    function testGetMaxLtv() external view {
        CollateralTokenConfig memory config = tokensConfig[0];
        MarketParams memory marketParams = morpho.idToMarketParams(
            Id.wrap(config.morphoMarketId)
        );

        uint256 expectedMaxLtv = marketParams.lltv - liquidationBuffer;

        assertEq(
            flc.getMaxLtv(config.collateralToken, marketParams.loanToken),
            expectedMaxLtv
        );
    }

    function testGetCollateralValueInLoanToken() external view {
        for (uint256 i; i < 4; ++i) {
            CollateralTokenConfig memory config = tokensConfig[i];
            MarketParams memory marketParams = morpho.idToMarketParams(
                Id.wrap(config.morphoMarketId)
            );

            uint256 amountCollateral = 10e18;
            address loanToken = marketParams.loanToken;
            uint8 loanTokenDecimals = IERC20Metadata(loanToken).decimals();

            uint256 expectedCollateralValueInLoanToken = IOracle(
                marketParams.oracle
            ).price().mulDown(amountCollateral).scaleTo(
                    Math.STANDARD_DECIMALS + loanTokenDecimals,
                    Math.STANDARD_DECIMALS
                );

            assertEq(
                flc.getCollateralValueInLoanToken(
                    config.collateralToken,
                    loanToken,
                    amountCollateral
                ),
                expectedCollateralValueInLoanToken
            );
        }
    }

    function testCalcFlashLoanAmount() external view {}
}
