// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import "./TestBase.t.sol";

/**
 * @title FlashLeverageCore Test Suite
 * @notice Comprehensive test coverage for FlashLeverageCore contract functionality
 * @dev Tests organized by functional areas: leveraging, unleveraging, access control, and views
 * @dev All tests follow the AAA (Arrange, Act, Assert) pattern for consistency and readability
 */
contract TestFlashLeverageCore is TestBase {
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

    function test_setManager_AssignsManager() external {
        // Arrange
        address newManager = makeAddr("New Manager");
        address flcOwner = flc.owner();

        // Act
        vm.prank(flcOwner);
        flc.addManager(newManager);

        // Assert
        assertTrue(
            flc.isManager(newManager),
            "Manager should be assigned successfully"
        );
    }

    function test_setManager_RevertsWhen_CalledByNonOwner() external {
        // Arrange
        address newManager = makeAddr("New Manager");

        // Act & Assert
        vm.expectRevert();
        flc.addManager(newManager);
    }

    function test_addSupportedCollateralTokens() external {
        // Arrange
        address flcOwner = flc.owner();
        CollateralTokenConfig[]
            memory newTokenConfig = new CollateralTokenConfig[](1);
        // PT-cUSD-29JAN2026
        newTokenConfig[0] = CollateralTokenConfig({
            collateralToken: 0x545A490f9ab534AdF409A2E682bc4098f49952e3,
            morphoMarketId: 0x802ec6e878dc9fe6905b8a0a18962dcca10440a87fa2242fbf4a0461c7b0c789,
            pendleMarket: 0x307c15f808914Df5a5DbE17E5608f84953fFa023
        });

        // Act
        vm.prank(flcOwner);
        flc.addSupportedCollateralTokens(newTokenConfig);

        // Assert
        bool supported = flc.isSupportedCollateralToken(
            newTokenConfig[0].collateralToken,
            USDC
        );
        assertTrue(supported);
    }

    function test_addSupportedCollateralTokens_RevertsWhen_InvalidTokenConfiguration()
        external
    {
        // Arrange
        address flcOwner = flc.owner();
        CollateralTokenConfig[]
            memory newTokenConfig = new CollateralTokenConfig[](1);

        // Case 1 - Invalid Collateral Token for given morpho Market
        newTokenConfig[0] = CollateralTokenConfig({
            collateralToken: 0x545A490f9ab534AdF409A2E682bc4098f49952e3,
            morphoMarketId: 0x8a71a66ac828c2b6d4f8accce5859aba0822b502f3833bec4aff09479affffdb,
            pendleMarket: 0x307c15f808914Df5a5DbE17E5608f84953fFa023
        });

        // Act & Assert
        vm.prank(flcOwner);
        vm.expectRevert(
            FLCError.FlashLeverageCore__InvalidCollateralToken.selector
        );
        flc.addSupportedCollateralTokens(newTokenConfig);

        // Case 2 - Collateral Token is not PT
        newTokenConfig[0] = CollateralTokenConfig({
            collateralToken: 0x3EAf6C8425b40c554099BEEd4DcB9f4601942fcb,
            morphoMarketId: 0x8a71a66ac828c2b6d4f8accce5859aba0822b502f3833bec4aff09479affffdb,
            pendleMarket: 0x307c15f808914Df5a5DbE17E5608f84953fFa023
        });

        // Act & Assert
        vm.prank(flcOwner);
        vm.expectRevert(
            FLCError.FlashLeverageCore__InvalidCollateralToken.selector
        );
        flc.addSupportedCollateralTokens(newTokenConfig);

        // Case 3 - Collateral Token has 6 decimals
        newTokenConfig[0] = CollateralTokenConfig({
            collateralToken: 0x00026E3311937BAd48D9Ab894c42134306E1698D,
            morphoMarketId: 0xa315e92e30a1f0e76df5e18d05a1b5c021fe809f989a9d7c0a5585a0f94e34ed,
            pendleMarket: 0x8f7EdDFa1A03D872Da73d9588B040b608238f863
        });

        // Act & Assert
        vm.prank(flcOwner);
        vm.expectRevert(
            FLCError.FlashLeverageCore__InvalidCollateralTokenDecimals.selector
        );
        flc.addSupportedCollateralTokens(newTokenConfig);
    }

    /*//////////////////////////////////////////////////////////////
                           LEVERAGE FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_leverage_RevertsWhen_CallerIsNotManager() external {
        // Arrange
        LeverageParams memory params = _buildDefaultLeverageParams();

        // Act & Assert
        vm.expectRevert(FLCError.FlashLeverageCore__NotAManager.selector);
        flc.leverage(USER, params);
    }

    function test_leverage_RevertsWhen_CollateralTokenUnsupported() external {
        // Arrange
        LeverageParams memory params = _buildDefaultLeverageParams();
        params.collateralToken = RANDOM_ADDRESS;

        // Act & Assert
        vm.expectRevert(
            FLCError.FlashLeverageCore__UnsupportedCollateralToken.selector
        );
        vm.prank(address(fl));
        flc.leverage(USER, params);
    }

    function test_leverage_RevertsWhen_CollateralAmountIsZero() external {
        // Arrange
        LeverageParams memory params = _buildDefaultLeverageParams();
        params.amountCollateral = 0;

        // Act & Assert
        vm.expectRevert(
            FLCError.FlashLeverageCore__AmountCollateralCannotBeZero.selector
        );
        vm.prank(address(fl));
        flc.leverage(USER, params);
    }

    function test_leverage_RevertsWhen_DesiredLtvExceedsMaxLtv() external {
        // Arrange
        LeverageParams memory params = _buildDefaultLeverageParams();
        uint256 EXCESSIVE_LTV = 90e16;
        params.desiredLtv = EXCESSIVE_LTV;

        // Act & Assert
        vm.expectRevert(FLCError.FlashLeverageCore__ExceedsMaxLTV.selector);
        vm.prank(address(fl));
        flc.leverage(USER, params);
    }

    function test_leverage_RevertsWhen_CollateralTransferFails() external {
        // Arrange
        LeverageParams memory params = _buildDefaultLeverageParams();
        // Note: USER doesn't have sufficient balance in this test

        // Act & Assert
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        vm.prank(address(fl));
        flc.leverage(USER, params);
    }

    function test_leverage_SuccessfullyCreatesPosition() external {
        // Arrange
        _setupSuccessfulLeverageConditions();

        // Act
        _executeLeverageOperation();

        // Assert
        CoreLeveragePosition memory position = flc.getUserCoreLeveragePosition(
            USER,
            DESIRED_LTV,
            COLLATERAL_TOKEN,
            LOAN_TOKEN
        );

        // 1. Verify position creation
        assertGt(
            position.amountCollateral,
            AMOUNT_COLLATERAL,
            "Collateral should increase due to leverage"
        );
        assertGt(position.sharesBorrowed, 0, "Should have borrowed shares");

        // 2. Verify effective LTV stays within acceptable bounds
        uint256 maxEffectiveLtv = DESIRED_LTV + slippageBuffer;
        uint256 collateralValue = flc.getCollateralValueInLoanToken(
            COLLATERAL_TOKEN,
            LOAN_TOKEN,
            position.amountCollateral
        );
        uint256 borrowedValue = flc.getSharesValueInLoanToken(
            COLLATERAL_TOKEN,
            LOAN_TOKEN,
            position.sharesBorrowed
        );
        uint256 effectiveLtv = borrowedValue.divDown(collateralValue);

        assertGt(
            effectiveLtv,
            DESIRED_LTV,
            "Effective LTV should be greater than desired due to slippage"
        );
        assertLe(
            effectiveLtv,
            maxEffectiveLtv,
            "Effective LTV should not exceed maximum allowed"
        );

        // 3. Verify user position isolation through userProxy
        address userProxy = flc.getUserProxy(USER, DESIRED_LTV);
        Position memory morphoPosition = morpho.position(
            Id.wrap(tokensConfig[0].morphoMarketId),
            userProxy
        );

        assertEq(
            morphoPosition.collateral,
            position.amountCollateral,
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

    function test_unleverage_RevertsWhen_CallerIsNotManager() external {
        // Arrange
        UnleverageParams memory params = _buildDefaultUnleverageParams(0, 0);

        // Act & Assert
        vm.expectRevert(FLCError.FlashLeverageCore__NotAManager.selector);
        flc.unleverage(USER, params);
    }

    function test_unleverage_RevertsWhen_SharesToBurnIsZero() external {
        // Arrange
        UnleverageParams memory params = _buildDefaultUnleverageParams(0, 0);

        // Act & Assert
        vm.expectRevert(
            FLCError.FlashLeverageCore__SharesToBurnCannotBeZero.selector
        );
        vm.prank(address(fl));
        flc.unleverage(USER, params);
    }

    function test_unleverage_RevertsWhen_BurningMoreSharesThanOwned() external {
        // Arrange
        uint256 sharesToBurn = 1;
        UnleverageParams memory params = _buildDefaultUnleverageParams(
            sharesToBurn,
            0
        );

        // Act & Assert
        vm.expectRevert(
            FLCError.FlashLeverageCore__InsufficientSharesToBurn.selector
        );
        vm.prank(address(fl));
        flc.unleverage(USER, params);
    }

    function test_unleverage_RevertsWhen_WithdrawingMoreCollateralThanDeposited()
        external
    {
        // Arrange
        uint256 sharesToBurn = 1;
        uint256 amountCollateralToWithdraw = 1;
        UnleverageParams memory params = _buildDefaultUnleverageParams(
            sharesToBurn,
            amountCollateralToWithdraw
        );

        // Act & Assert
        vm.expectRevert(
            FLCError
                .FlashLeverageCore__InsufficientCollateralToWithdraw
                .selector
        );
        vm.prank(address(fl));
        flc.unleverage(USER, params);
    }

    function test_unleverage_SuccessfullyReducesPosition()
        external
        withLeveragedPosition
    {
        // Arrange
        CoreLeveragePosition memory positionBefore = flc
            .getUserCoreLeveragePosition(
                USER,
                DESIRED_LTV,
                COLLATERAL_TOKEN,
                LOAN_TOKEN
            );

        // Act
        _executeUnleverageOperation(
            positionBefore.sharesBorrowed,
            positionBefore.amountCollateral
        );

        // Assert
        CoreLeveragePosition memory positionAfter = flc
            .getUserCoreLeveragePosition(
                USER,
                DESIRED_LTV,
                COLLATERAL_TOKEN,
                LOAN_TOKEN
            );

        assertEq(
            positionAfter.sharesBorrowed,
            0,
            "Position should be completely closed"
        );
        assertEq(
            positionAfter.amountCollateral,
            0,
            "All collateral should be withdrawn"
        );
    }

    /*//////////////////////////////////////////////////////////////
                         FLASHLOAN CALLBACK TESTS
    //////////////////////////////////////////////////////////////*/

    function test_flashLoanCallback_RevertsWhen_CalledDirectly() external {
        // Arrange
        uint256 amountLoan = 100e18;
        bytes memory data = "0x";

        // Act & Assert
        vm.expectRevert(FLCError.FlashLeverageCore__UntrustedLender.selector);
        flc.onMorphoFlashLoan(amountLoan, data);
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
        flc.onMorphoFlashLoan(amountLoan, data);
    }

    /*//////////////////////////////////////////////////////////////
                         USER PROXY TESTS
    //////////////////////////////////////////////////////////////*/

    function test_getOrCreateUserProxy_CreatesNewProxyWhenNoneExists()
        external
    {
        // Arrange
        // No existing proxy for this user/LTV combination

        // Act
        address createdProxy = flc.getOrCreateUserProxy(USER, DESIRED_LTV);
        address retrievedProxy = flc.getUserProxy(USER, DESIRED_LTV);

        // Assert
        assertNotEq(
            createdProxy,
            address(0),
            "Proxy address should not be zero"
        );
        assertEq(
            retrievedProxy,
            createdProxy,
            "Retrieved proxy should match created proxy"
        );
    }

    function test_getOrCreateUserProxy_ReusesExistingProxy() external {
        // Arrange
        address proxyBefore = flc.getOrCreateUserProxy(USER, DESIRED_LTV);

        // Act
        address proxyAfter = flc.getOrCreateUserProxy(USER, DESIRED_LTV);

        // Assert
        assertEq(
            proxyAfter,
            proxyBefore,
            "Should reuse existing proxy instead of creating new one"
        );
    }

    function test_userProxy_OnlyExecutableByFlashLeverageCore() external {
        // Arrange
        UserProxy userProxy = UserProxy(flc.i_userProxyImplementation());
        address randomAddress = makeAddr("random");

        // Act & Assert - Should succeed when called by FLC
        vm.prank(address(flc));
        userProxy.execute(randomAddress, "0x");

        // Should revert when called by anyone else
        vm.expectRevert();
        userProxy.execute(randomAddress, "0x");
    }

    /*//////////////////////////////////////////////////////////////
                           VIEW FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_contractAddresses_AreSetCorrectly() external view {
        // Arrange
        // Contract should be properly initialized

        // Act
        address morphoAddress = address(flc.i_morpho());
        address pendleRouterAddress = address(flc.i_pendleRouter());
        address proxyImplementation = flc.i_userProxyImplementation();

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

    function test_bufferValues_AreSetCorrectly() external view {
        // Arrange
        // Contract should be properly initialized

        // Act
        uint256 liqBuffer = flc.i_liquidationBuffer();
        uint256 slipBuffer = flc.i_slippageBuffer();

        // Assert
        assertEq(
            liqBuffer,
            liquidationBuffer,
            "Liquidation buffer should match"
        );
        assertEq(slipBuffer, slippageBuffer, "Slippage buffer should match");
    }

    function test_getLiqLtv_ReturnsCorrectValue() external view {
        // Arrange
        CollateralTokenConfig memory config = tokensConfig[0];
        MarketParams memory marketParams = morpho.idToMarketParams(
            Id.wrap(config.morphoMarketId)
        );

        // Act
        uint256 actualLiqLtv = flc.getLiqLtv(
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
        CollateralTokenConfig memory config = tokensConfig[0];
        MarketParams memory marketParams = morpho.idToMarketParams(
            Id.wrap(config.morphoMarketId)
        );
        uint256 expectedMaxLtv = marketParams.lltv - liquidationBuffer;

        // Act
        uint256 actualMaxLtv = flc.getMaxLtv(
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
        for (uint256 i; i < 4; ++i) {
            CollateralTokenConfig memory config = tokensConfig[i];
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

            uint256 actualValue = flc.getCollateralValueInLoanToken(
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
        uint256 collateralValue = flc.getCollateralValueInLoanToken(
            COLLATERAL_TOKEN,
            LOAN_TOKEN,
            AMOUNT_COLLATERAL
        );
        uint256 expectedAmount = ((
            collateralValue.divDown(Math.ONE - DESIRED_LTV)
        ) - collateralValue).scaleTo(18, 6);

        // Act
        uint256 actualAmount = flc.calcLeverageFlashLoan(
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
        uint256 collateralValue = flc
            .getCollateralValueInLoanToken(
                COLLATERAL_TOKEN,
                LOAN_TOKEN,
                AMOUNT_COLLATERAL
            )
            .scaleTo(Math.STANDARD_DECIMALS, LOAN_TOKEN_DECIMALS);

        // Act
        uint256 loanAmount = flc.calcLeverageFlashLoan(
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
        IERC20(COLLATERAL_TOKEN).approve(address(flc), AMOUNT_COLLATERAL);
    }

    function _executeLeverageOperation() internal {
        bytes memory callData = getLeverageCalldata(
            USER,
            DESIRED_LTV,
            COLLATERAL_TOKEN,
            LOAN_TOKEN,
            AMOUNT_COLLATERAL
        );

        vm.prank(address(fl));
        (bool success, ) = address(flc).call(callData);
        require(success, "Leverage operation failed");
    }

    function _executeUnleverageOperation(
        uint256 sharesToBurn,
        uint256 amountCollateralToWithdraw
    ) internal {
        bytes memory callData = getCoreUnleverageCalldata(
            USER,
            DESIRED_LTV,
            COLLATERAL_TOKEN,
            sharesToBurn,
            amountCollateralToWithdraw
        );

        vm.prank(address(fl));
        (bool success, ) = address(flc).call(callData);
        require(success, "Unleverage operation failed");
    }
}
