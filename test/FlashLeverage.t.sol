// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import "./TestBase.t.sol";

/**
 * @title FlashLeverage Test Suite
 * @notice Test coverage for FlashLeverage contract functionality
 * @dev All tests follow the AAA (Arrange, Act, Assert) pattern for consistency
 */
contract TestFlashLeverage is TestBase {
    using Math for uint256;

    /*//////////////////////////////////////////////////////////////
                        STATEFUL TESTING MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier withLeveragedPosition() {
        _executeLeverageOperation();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                           LEVERAGE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_leverage_RevertsWhen_CollateralTokenUnsupported() external {
        // Arrange
        LeverageParams memory params = _buildDefaultLeverageParams();
        params.collateralToken = RANDOM_ADDRESS;

        // Act & Assert
        vm.expectRevert(
            FLError.FlashLeverage__UnsupportedCollateralToken.selector
        );
        fl.leverage(USER, params);
    }

    function test_leverage_RevertsWhen_CollateralAmountIsZero() external {
        // Arrange
        LeverageParams memory params = _buildDefaultLeverageParams();
        params.amountCollateral = 0;

        // Act & Assert
        vm.expectRevert(FLError.FlashLeverage__AmountCannotBeZero.selector);
        fl.leverage(USER, params);
    }

    function test_leverage_RevertsWhen_DesiredLtvExceedsMaxLtv() external {
        // Arrange
        LeverageParams memory params = _buildDefaultLeverageParams();
        uint256 EXCESSIVE_LTV = 90e16;
        params.desiredLtv = EXCESSIVE_LTV;

        // Act & Assert
        vm.expectRevert(FLError.FlashLeverage__ExceedsMaxLTV.selector);
        fl.leverage(USER, params);
    }

    function test_leverage_SuccessfullyCreatesPosition() external {
        // Arrange
        _setupLeverageConditions();

        // Act
        _executeLeverageOperation();

        // Assert
        LeveragePosition memory leveragePosition = fl.getUserLeveragePosition(
            USER,
            0
        );

        CoreLeveragePosition memory coreLeveragePosition = flc
            .getUserCoreLeveragePosition(
                USER,
                DESIRED_LTV,
                COLLATERAL_TOKEN,
                LOAN_TOKEN
            );

        assertEq(leveragePosition.open, true);
        assertEq(leveragePosition.desiredLtv, DESIRED_LTV);
        assertEq(leveragePosition.collateralToken, COLLATERAL_TOKEN);
        assertEq(leveragePosition.loanToken, LOAN_TOKEN);
        assertEq(leveragePosition.amountCollateral, AMOUNT_COLLATERAL);
        assertEq(
            leveragePosition.amountCollateralInLoanToken,
            flc
                .getCollateralValueInLoanToken(
                    COLLATERAL_TOKEN,
                    LOAN_TOKEN,
                    AMOUNT_COLLATERAL
                )
                .scaleTo(Math.STANDARD_DECIMALS, LOAN_TOKEN_DECIMALS)
        );
        assertEq(
            leveragePosition.amountLeveragedCollateral,
            coreLeveragePosition.amountCollateral
        );
        assertEq(
            leveragePosition.sharesBorrowed,
            coreLeveragePosition.sharesBorrowed
        );
    }

    /*//////////////////////////////////////////////////////////////
                           UNLEVERAGE FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_unleverage_RevertsWhen_PositionDoesNotExist() external {
        // Arrange
        uint256 positionId = 0;
        address pendleSwap;
        address tokenRedeemSy;
        SwapData memory swapData;
        LimitOrderData memory limitOrderData;

        // Act & Assert
        vm.expectRevert(FLError.FlashLeverage__PositionDoesNotExist.selector);
        fl.unleverage(
            positionId,
            pendleSwap,
            tokenRedeemSy,
            swapData,
            limitOrderData
        );
    }

    function test_unleverage_SucessfullyClosesPosition_AndRevertsForAlreadyClosedPosition()
        external
    {}

    /*//////////////////////////////////////////////////////////////
                           VIEW FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_pendleRouterAddress_IsSetCorrectly() external view {
        // Arrange
        address expectedPendleRouter = pendleRouter;

        // Act
        address actualPendleRouter = address(fl.i_pendleRouter());

        // Assert
        assertEq(actualPendleRouter, expectedPendleRouter);
    }

    function test_flashLeverageCoreAddress_IsSetCorrectly() external view {
        // Arrange
        address expectedFlashLeverage = address(flc);

        // Act
        address actualFlashLeverageCore = address(fl.i_flashLeverageCore());

        // Assert
        assertEq(actualFlashLeverageCore, expectedFlashLeverage);
    }

    function test_treasuryAddress_IsSetCorrectly() external view {
        // Arrange
        address expectedTreasury = treasury;

        // Act
        address actualTreasury = fl.getTreasury();

        // Assert
        assertEq(actualTreasury, expectedTreasury);
    }

    function test_isSupportedCollateralToken_CorrectlyIdentifiesTokens()
        external
    {
        // Arrange & Act & Assert
        for (uint256 i; i < tokensConfig.length; ++i) {
            address collateralToken = tokensConfig[i].collateralToken;
            assertTrue(fl.isSupportedCollateralToken(collateralToken));
        }

        // For unsupported collateral token
        address unsupportedCollateralToken = makeAddr("randomAddress");
        assertFalse(fl.isSupportedCollateralToken(unsupportedCollateralToken));
    }

    /*//////////////////////////////////////////////////////////////
                           HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _setupLeverageConditions() internal {
        vm.prank(USER);
        IERC20(COLLATERAL_TOKEN).approve(address(fl), AMOUNT_COLLATERAL);
    }

    function _executeLeverageOperation() internal {
        // Arrange
        bytes memory leverageCallData = getLeverageCalldata(
            USER,
            DESIRED_LTV,
            COLLATERAL_TOKEN,
            LOAN_TOKEN,
            AMOUNT_COLLATERAL
        );

        vm.prank(USER);
        IERC20(COLLATERAL_TOKEN).approve(address(fl), AMOUNT_COLLATERAL);

        // Act
        vm.prank(USER);
        (bool success, ) = address(fl).call(leverageCallData);

        // Assert
        require(success, "Leverage Call Failed");
    }
}
