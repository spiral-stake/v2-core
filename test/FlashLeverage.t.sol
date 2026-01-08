// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import "./TestBase.t.sol";

/**
 * @title FlashLeverage Test Suite
 * @notice Comprehensive test coverage for FlashLeverage contract functionality
 * @dev Tests organized by functional areas: leveraging, deleveraging, access control, and views
 * @dev All tests follow the AAA (Arrange, Act, Assert) pattern for consistency and readability
 */
contract TestFlashLeverage is TestBase {
    using Math for uint256;

    /*//////////////////////////////////////////////////////////////
                        STATEFUL TESTING MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier withLeveragedPosition() {
        _setupSuccessfulLeverageConditions();
        _executeLeverageOperation();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                           ACCESS CONTROL TESTS
    //////////////////////////////////////////////////////////////*/

    function test_addSupportedCollateralTokens() external {
        // Arrange
        address flOwner = fl.owner();
        CollateralTokenConfig[]
            memory newTokenConfig = new CollateralTokenConfig[](1);

        // Required
        // PT-cUSD
        newTokenConfig[0] = CollateralTokenConfig({
            collateralToken: 0x545A490f9ab534AdF409A2E682bc4098f49952e3,
            morphoMarketId: 0x802ec6e878dc9fe6905b8a0a18962dcca10440a87fa2242fbf4a0461c7b0c789,
            pendleMarket: 0x307c15f808914Df5a5DbE17E5608f84953fFa023
        });

        // Act
        vm.prank(flOwner);
        fl.addSupportedCollateralTokens(newTokenConfig);

        // Assert
        bool supported = fl.isSupportedCollateralToken(
            newTokenConfig[0].collateralToken,
            USDC
        );
        assertTrue(supported);
    }

    function test_addSupportedCollateralTokens_RevertsWhen_InvalidTokenConfiguration()
        external
    {
        // Arrange
        address flOwner = fl.owner();
        CollateralTokenConfig[]
            memory newTokenConfig = new CollateralTokenConfig[](1);

        // Case 1 - Invalid Collateral Token for given morpho Market
        newTokenConfig[0] = CollateralTokenConfig({
            collateralToken: 0x545A490f9ab534AdF409A2E682bc4098f49952e3,
            morphoMarketId: 0x8a71a66ac828c2b6d4f8accce5859aba0822b502f3833bec4aff09479affffdb,
            pendleMarket: 0x307c15f808914Df5a5DbE17E5608f84953fFa023
        });

        // Act & Assert
        vm.prank(flOwner);
        vm.expectRevert(FLError.FlashLeverage__InvalidCollateralToken.selector);
        fl.addSupportedCollateralTokens(newTokenConfig);
    }

    /*//////////////////////////////////////////////////////////////
                           LEVERAGE FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_leverage_RevertsWhen_CollateralTokenUnsupported() external {
        // Arrange
        LeverageParams memory params = _buildDefaultLeverageParams();
        params.collateralToken = RANDOM_ADDRESS;

        // Act & Assert
        vm.expectRevert(
            FLError.FlashLeverage__UnsupportedCollateralToken.selector
        );
        vm.prank(address(fl));
        fl.leverage(USER, params);
    }

    function test_leverage_RevertsWhen_CollateralAmountIsZero() external {
        // Arrange
        LeverageParams memory params = _buildDefaultLeverageParams();
        params.amountCollateral = 0;

        // Act & Assert
        vm.expectRevert(FLError.FlashLeverage__AmountCannotBeZero.selector);
        vm.prank(address(fl));
        fl.leverage(USER, params);
    }

    function test_leverage_RevertsWhen_DesiredLtvExceedsMaxLtv() external {
        // Arrange
        LeverageParams memory params = _buildDefaultLeverageParams();
        uint256 EXCESSIVE_LTV = 90e16;
        params.desiredLtv = EXCESSIVE_LTV;

        // Act & Assert
        vm.expectRevert(FLError.FlashLeverage__ExceedsMaxLTV.selector);
        vm.prank(address(fl));
        fl.leverage(USER, params);
    }

    function test_leverage_RevertsWhen_CollateralTransferFails() external {
        // Arrange
        LeverageParams memory params = _buildDefaultLeverageParams();

        // Case 1: USER doesn't have sufficient allowance to the flashLeverage contract
        // Act & Assert
        vm.expectRevert("ERC20: insufficient allowance");
        vm.prank(RANDOM_ADDRESS);
        fl.leverage(USER, params);

        // Case 2: USER doesn't have sufficient balance
        // Act & Assert
        vm.prank(RANDOM_ADDRESS);
        IERC20(COLLATERAL_TOKEN).approve(address(fl), AMOUNT_COLLATERAL);

        vm.expectRevert("ERC20: transfer amount exceeds balance");
        vm.prank(RANDOM_ADDRESS);
        fl.leverage(USER, params);
    }

    function test_leverage_SuccessfullyCreatesPosition() external {
        // Arrange
        _setupSuccessfulLeverageConditions();

        // Act
        _executeLeverageOperation();

        // Assert
        LeveragePosition memory position = fl.getUserLeveragePosition(USER, 0);

        // 1. Verify position creation
        assertEq(position.open, true);
        assertEq(position.amountCollateral, AMOUNT_COLLATERAL);
        assertGt(position.sharesBorrowed, 0, "Shares Borrowed should be gt 0");

        // 3. Verify user position isolation through userProxy
        address userProxy = position.userProxy;
        Position memory morphoPosition = morpho.position(
            Id.wrap(tokenConfigs[TOKEN_INDEX].morphoMarketId),
            userProxy
        );

        assertEq(
            morphoPosition.collateral,
            position.amountLeveragedCollateral,
            "Morpho position collateral should match core position"
        );
        assertEq(
            morphoPosition.borrowShares,
            position.sharesBorrowed,
            "Morpho position shares should match core position"
        );
    }

    /*//////////////////////////////////////////////////////////////
                           UNLEVERAGE FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_deleverage_SuccessfullyClosesPosition_AndRevertsForAlreadyClosedPosition()
        external
        withLeveragedPosition
    {
        uint256 positionId = 0;
        // Arrange
        LeveragePosition memory positionBefore = fl.getUserLeveragePosition(
            USER,
            positionId
        );

        // Act
        _executeDeleverageOperation(
            positionId,
            positionBefore.amountLeveragedCollateral
        );

        // Assert
        LeveragePosition memory positionAfter = fl.getUserLeveragePosition(
            USER,
            positionId
        );
        assertEq(positionAfter.open, false);

        // Revert for already closed position
        vm.expectRevert(FLError.FlashLeverage__PositionAlreadyClosed.selector);
        _executeDefaultDeleverageOperation(positionId);
    }

    function test_deleverage_RevertsWhen_PositionDoesNotExist() external {
        // Act & Assert
        vm.expectRevert("panic: array out-of-bounds access (0x32)");
        _executeDefaultDeleverageOperation(0);
    }

    /*//////////////////////////////////////////////////////////////
                         FLASHLOAN CALLBACK TESTS
    //////////////////////////////////////////////////////////////*/

    function test_flashLoanCallback_RevertsWhen_CalledDirectly() external {
        // Arrange
        uint256 amountLoan = 100e18;
        bytes memory data = "0x";

        // Act & Assert
        vm.expectRevert(FLError.FlashLeverage__UntrustedLender.selector);
        fl.onMorphoFlashLoan(amountLoan, data);
    }

    function test_flashLoanCallback_RevertsWhen_CalledWithInvalidData()
        external
    {
        // Arrange
        uint256 amountLoan = 100e18;
        bytes memory data = "0x"; // Invalid data format

        // Act & Assert
        vm.expectRevert();
        vm.prank(address(morpho));
        fl.onMorphoFlashLoan(amountLoan, data);
    }

    /*//////////////////////////////////////////////////////////////
                         USER PROXY TESTS
    //////////////////////////////////////////////////////////////*/

    function test_userProxy_OnlyExecutableByFlashLeverage() external {
        // Arrange
        UserProxy userProxy = UserProxy(fl.i_userProxyImplementation());

        // Should revert when called by anyone else
        vm.expectRevert("UserProxy: Unauthorised");
        userProxy.execute("0x");
    }

    /*//////////////////////////////////////////////////////////////
                           VIEW FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_contractAddresses_AreSetCorrectly() external view {
        // Arrange
        // Contract should be properly initialized

        // Act
        address morphoAddress = address(fl.i_morpho());
        address pendleRouterAddress = address(fl.s_pendleRouter());
        address proxyImplementation = fl.i_userProxyImplementation();

        // Assert
        assertEq(morphoAddress, address(morpho), "Morpho address should match");
        assertEq(
            pendleRouterAddress,
            pendleRouter,
            "Pendle router address should match"
        );
        assertNotEq(
            proxyImplementation,
            address(0),
            "User proxy implementation should be set"
        );
    }

    function test_getLiqLtv_ReturnsCorrectValue() external view {
        // Arrange
        CollateralTokenConfig memory config = tokenConfigs[TOKEN_INDEX];
        MarketParams memory marketParams = morpho.idToMarketParams(
            Id.wrap(config.morphoMarketId)
        );

        // Act
        uint256 actualLiqLtv = fl.getLiqLtv(
            config.collateralToken,
            marketParams.loanToken
        );

        // Assert
        assertEq(
            actualLiqLtv,
            marketParams.lltv,
            "Liquidation LTV should match market parameters"
        );
    }

    function test_getMaxLtv_ReturnsLiqLtvMinusBuffer() external view {
        // Arrange
        CollateralTokenConfig memory config = tokenConfigs[TOKEN_INDEX];
        MarketParams memory marketParams = morpho.idToMarketParams(
            Id.wrap(config.morphoMarketId)
        );
        uint256 liquidationBuffer = fl.LIQUIDATION_BUFFER();
        uint256 expectedMaxLtv = marketParams.lltv - liquidationBuffer;

        // Act
        uint256 actualMaxLtv = fl.getMaxLtv(
            config.collateralToken,
            marketParams.loanToken
        );

        // Assert
        assertEq(
            actualMaxLtv,
            expectedMaxLtv,
            "Max LTV should equal liquidation LTV minus buffer"
        );
    }

    function test_getCollateralValueInLoanToken_CalculatesCorrectly()
        external
        view
    {
        // Arrange & Act & Assert
        // Test across multiple token configurations for comprehensive coverage
        for (uint256 i; i < tokenConfigs.length; ++i) {
            CollateralTokenConfig memory config = tokenConfigs[i];
            MarketParams memory marketParams = morpho.idToMarketParams(
                Id.wrap(config.morphoMarketId)
            );

            uint256 amountCollateral = 10e18;
            address loanToken = marketParams.loanToken;
            uint8 loanTokenDecimals = IERC20Metadata(loanToken).decimals();

            // Calculate expected value using oracle price
            uint256 expectedValue = IOracle(marketParams.oracle)
                .price()
                .mulDown(amountCollateral)
                .scaleTo(
                    Math.STANDARD_DECIMALS + loanTokenDecimals,
                    Math.STANDARD_DECIMALS
                );

            uint256 actualValue = fl.getCollateralValueInLoanToken(
                config.collateralToken,
                loanToken,
                amountCollateral
            );

            assertEq(
                actualValue,
                expectedValue,
                string(
                    abi.encodePacked(
                        "Collateral value calculation failed for token ",
                        vm.toString(i)
                    )
                )
            );
        }
    }

    /*//////////////////////////////////////////////////////////////
                        FLASH LOAN CALCULATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_calcLeverageFlashLoan_ReturnsCorrectAmount() external view {
        // Arrange
        uint256 collateralValue = fl.getCollateralValueInLoanToken(
            COLLATERAL_TOKEN,
            LOAN_TOKEN,
            AMOUNT_COLLATERAL
        );
        uint256 expectedAmount = ((
            collateralValue.divDown(Math.ONE - DESIRED_LTV)
        ) - collateralValue).scaleTo(
                Math.STANDARD_DECIMALS,
                LOAN_TOKEN_DECIMALS
            );

        // Act
        uint256 actualAmount = fl.calcLeverageFlashLoan(
            DESIRED_LTV,
            COLLATERAL_TOKEN,
            LOAN_TOKEN,
            AMOUNT_COLLATERAL
        );

        // Assert
        assertEq(
            actualAmount,
            expectedAmount,
            "Flash loan amount calculation should be correct"
        );
    }

    function test_calcLeverageFlashLoan_ProducesDesiredLtv() external view {
        // Arrange
        uint256 collateralValue = fl
            .getCollateralValueInLoanToken(
                COLLATERAL_TOKEN,
                LOAN_TOKEN,
                AMOUNT_COLLATERAL
            )
            .scaleTo(Math.STANDARD_DECIMALS, LOAN_TOKEN_DECIMALS);

        // Act
        uint256 loanAmount = fl.calcLeverageFlashLoan(
            DESIRED_LTV,
            COLLATERAL_TOKEN,
            LOAN_TOKEN,
            AMOUNT_COLLATERAL
        );

        uint256 actualLtv = loanAmount.divDown(collateralValue + loanAmount);

        // Assert
        assertEq(
            actualLtv.scaleTo(Math.STANDARD_DECIMALS, LOAN_TOKEN_DECIMALS),
            DESIRED_LTV.scaleTo(Math.STANDARD_DECIMALS, LOAN_TOKEN_DECIMALS),
            "Calculated LTV should match desired LTV"
        );
    }

    /*//////////////////////////////////////////////////////////////
                            HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _setupSuccessfulLeverageConditions() internal {
        vm.prank(USER);
        IERC20(COLLATERAL_TOKEN).transfer(address(fl), AMOUNT_COLLATERAL);

        vm.prank(address(fl));
        IERC20(COLLATERAL_TOKEN).approve(address(fl), AMOUNT_COLLATERAL);
    }

    function _executeLeverageOperation() internal {
        bytes memory callData = getLeverageCalldata(
            USER,
            DESIRED_LTV,
            COLLATERAL_TOKEN,
            LOAN_TOKEN,
            AMOUNT_COLLATERAL
        );

        vm.startPrank(USER);

        IERC20(COLLATERAL_TOKEN).approve(address(fl), AMOUNT_COLLATERAL);
        (bool success, ) = address(fl).call(callData);
        require(success, "Leverage operation failed");
        vm.stopPrank();
    }

    function _executeDeleverageOperation(
        uint256 positionId,
        uint256 amountLeveragedCollateral
    ) internal {
        bytes memory callData = getDeleverageCalldata(
            positionId,
            COLLATERAL_TOKEN,
            amountLeveragedCollateral
        );

        vm.prank(USER);
        (bool success, ) = address(fl).call(callData);
        require(success, "Deleverage operation failed");
    }

    function _executeDefaultDeleverageOperation(uint256 positionId) internal {
        address pendleSwap;
        address tokenRedeemSy;
        uint256 minTokenOut;
        SwapData memory swapData;
        LimitOrderData memory limitOrderData;

        vm.prank(USER);
        fl.deleverage(
            positionId,
            DeleverageParams({
                pendleSwap: pendleSwap,
                tokenRedeemSy: tokenRedeemSy,
                minTokenOut: minTokenOut,
                swapData: swapData,
                limitOrderData: limitOrderData
            })
        );
    }
}
