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
                               CONSTANTS
    //////////////////////////////////////////////////////////////*/

    address private constant USER = 0x925109e0AfFe306c31B55d8181e766D53aF7A778; // PT-USDE-WHALE
    uint256 private constant DESIRED_LTV = 80e16; // 80%
    address private constant COLLATERAL_TOKEN =
        0xBC6736d346a5eBC0dEbc997397912CD9b8FAe10a; // PT-USDE
    address private constant LOAN_TOKEN =
        0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // USDC
    uint8 private constant LOAN_TOKEN_DECIMALS = 6;
    uint256 private constant AMOUNT_COLLATERAL = 1000000e18;

    /*//////////////////////////////////////////////////////////////
                        STATEFUL TESTING MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier withLeveragedPosition() {
        _createLeveragedPosition();
        _;
    }

    modifier withMultipleLeveragedPositions() {
        _createLeveragedPosition();
        _createLeveragedPosition();
        _createLeveragedPosition();
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

    function test_addSupportedCollateralTokens_RevertsWhen_InvalidTokenConfiguration()
        external
    {
        // Arrange
        // TODO: Create invalid token configuration
        // Act
        // TODO: Call addSupportedCollateralTokens with invalid config
        // Assert
        // TODO: Verify proper revert
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

    function test_leverage_RevertsWhen_ReentrantCallAttempted() external {
        // Arrange
        // TODO: Setup reentrancy attack scenario
        // Act
        // TODO: Attempt reentrant call
        // Assert
        // TODO: Verify reentrancy protection works
    }

    function test_leverage_RevertsWhen_InsufficientLiquidityInMarket()
        external
    {
        // Arrange
        // TODO: Setup low liquidity scenario
        // Act
        // TODO: Attempt leverage operation
        // Assert
        // TODO: Verify proper revert
    }

    function test_leverage_RevertsWhen_EffectiveLtvExceedsSlippageBuffer()
        external
    {
        // Not Possible to mimick //
        // Arrange
        // Note: This scenario is difficult to simulate due to price oracle dependencies
        // Act
        // TODO: Create conditions where slippage is excessive
        // Assert
        // TODO: Verify slippage protection works
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

    function test_leverage_PositionRemainsConsistent_AfterMultipleOperations()
        external
    {
        // Arrange
        // TODO: Setup for multiple operations
        // Act
        // TODO: Execute multiple leverage operations
        // Assert
        // TODO: Verify position consistency
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

    function test_unleverage_RevertsWhen_ReentrantCallAttempted() external {
        // Arrange
        // TODO: Setup reentrancy attack scenario
        // Act
        // TODO: Attempt reentrant call
        // Assert
        // TODO: Verify reentrancy protection works
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

    function _buildDefaultLeverageParams()
        internal
        returns (LeverageParams memory)
    {
        ApproxParams memory approxParams;
        SwapData memory swapData;
        LimitOrderData memory limitOrderData;

        return
            LeverageParams({
                desiredLtv: DESIRED_LTV,
                collateralToken: COLLATERAL_TOKEN,
                loanToken: LOAN_TOKEN,
                amountCollateral: AMOUNT_COLLATERAL,
                approxParams: approxParams,
                pendleSwap: makeAddr("pendleSwap"),
                tokenMintSy: makeAddr("tokenMintSy"),
                swapData: swapData,
                limitOrderData: limitOrderData
            });
    }

    function _buildDefaultUnleverageParams(
        uint256 sharesToBurn,
        uint256 amountCollateralToWithdraw
    ) internal returns (UnleverageParams memory) {
        SwapData memory swapData;
        LimitOrderData memory limitOrderData;

        return
            UnleverageParams({
                desiredLtv: DESIRED_LTV,
                collateralToken: COLLATERAL_TOKEN,
                loanToken: LOAN_TOKEN,
                sharesToBurn: sharesToBurn,
                amountCollateralToWithdraw: amountCollateralToWithdraw,
                pendleSwap: makeAddr("pendleSwap"),
                tokenRedeemSy: makeAddr("tokenRedeemSy"),
                swapData: swapData,
                limitOrderData: limitOrderData
            });
    }

    function _createLeveragedPosition() internal {
        _setupSuccessfulLeverageConditions();
        _executeLeverageOperation();
    }

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
        bytes memory callData = getUnleverageCalldata(
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
