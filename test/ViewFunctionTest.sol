// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import "./TestBase.sol";

/// @title ViewFunctionTest
/// @notice Tests for view functions on FlashLeverage
contract ViewFunctionTest is TestBase {
    using Math for uint256;

    uint256 constant INITIAL_COLLATERAL = 10e18;
    uint256 constant STANDARD_LTV = 70e16; // 70%

    // ═══════════════════════════════════════════════
    //           MARKET SUPPORT
    // ═══════════════════════════════════════════════

    function test_isSupportedMarket_true() external view {
        assertTrue(fl.isSupportedMarket(correlatedMarketId));
        assertTrue(fl.isSupportedMarket(nonCorrelatedMarketId));
    }

    function test_isSupportedMarket_false_unknownMarket() external view {
        assertFalse(fl.isSupportedMarket(keccak256("unknown")));
    }

    function test_isSupportedMarket_false_disabledMarket() external {
        fl.setMarketEnabled(correlatedMarketId, false);
        assertFalse(fl.isSupportedMarket(correlatedMarketId));
    }

    function test_isSupportedMarket_trueAfterReEnable() external {
        fl.setMarketEnabled(correlatedMarketId, false);
        fl.setMarketEnabled(correlatedMarketId, true);
        assertTrue(fl.isSupportedMarket(correlatedMarketId));
    }

    function test_isCorrelated() external view {
        assertTrue(fl.s_isCorrelated(correlatedMarketId));
        assertFalse(fl.s_isCorrelated(nonCorrelatedMarketId));
    }

    // ═══════════════════════════════════════════════
    //          POSITION QUERIES
    // ═══════════════════════════════════════════════

    function test_getUserLeveragePositions_empty() external view {
        assertEq(fl.getUserLeveragePositions(alice).length, 0);
    }

    function test_getUserLeveragePositions_afterMultipleOpens() external {
        _openCorrelatedPosition(alice, INITIAL_COLLATERAL, STANDARD_LTV);
        _openCorrelatedPosition(alice, 5e18, 60e16);

        LeveragePosition[] memory positions = fl.getUserLeveragePositions(
            alice
        );
        assertEq(positions.length, 2);
        assertTrue(positions[0].open);
        assertTrue(positions[1].open);
        assertTrue(positions[0].userProxy != positions[1].userProxy);
    }

    function test_getUserLeveragePosition_allFields() external {
        uint256 posId = _openCorrelatedPosition(
            alice,
            INITIAL_COLLATERAL,
            STANDARD_LTV
        );

        LeveragePosition memory pos = fl.getUserLeveragePosition(alice, posId);
        assertTrue(pos.open);
        assertEq(pos.marketId, correlatedMarketId);
        assertTrue(pos.userProxy != address(0));
        assertGt(pos.amountDepositedInLoanToken, 0);
        assertEq(pos.amountReturnedInLoanToken, 0);
    }

    function test_getUserLeveragePosition_afterClose() external {
        uint256 posId = _openCorrelatedPosition(
            alice,
            INITIAL_COLLATERAL,
            STANDARD_LTV
        );
        _deleveragePosition(alice, posId, correlatedMarket);

        LeveragePosition memory pos = fl.getUserLeveragePosition(alice, posId);
        assertFalse(pos.open);
        assertGt(pos.amountReturnedInLoanToken, 0);
    }

    // ═══════════════════════════════════════════════
    //       COLLATERAL VALUE CONVERSION
    // ═══════════════════════════════════════════════

    function test_getCollateralValueInLoanToken_correlated_accuracy()
        external
        view
    {
        uint256 collateral = 10e18;
        uint256 value = fl.getCollateralValueInLoanToken(
            correlatedMarket,
            collateral
        );

        // 10 wstETH * 1.1 price = 11 WETH (both 18 decimals)
        // Oracle price = 1.1e36, mulDown(10e18, 1.1e36) = 11e36, then scaleTo(36, 18) = 11e18
        assertEq(value, 11e18, "10 wstETH at 1.1 price should equal 11 WETH");
    }

    function test_getCollateralValueInLoanToken_nonCorrelated_accuracy()
        external
        view
    {
        uint256 collateral = 1e18; // 1 ETH
        uint256 value = fl.getCollateralValueInLoanToken(
            nonCorrelatedMarket,
            collateral
        );

        // 1 ETH * 2000 price = 2000 USDC (18 -> 6 decimal scaling)
        // Oracle price = 2000e24, mulDown(1e18, 2000e24) = 2000e24, then scaleTo(24, 6) = 2000e6
        assertEq(value, 2000e6, "1 ETH at 2000 price should equal 2000 USDC");
    }

    function test_getCollateralValueInLoanToken_zero() external view {
        assertEq(fl.getCollateralValueInLoanToken(correlatedMarket, 0), 0);
    }

    function test_getCollateralValueInLoanToken_updatesWithOracle() external {
        uint256 collateral = 10e18;

        uint256 valueBefore = fl.getCollateralValueInLoanToken(
            correlatedMarket,
            collateral
        );

        correlatedOracle.setPrice(CORRELATED_PRICE * 2);

        uint256 valueAfter = fl.getCollateralValueInLoanToken(
            correlatedMarket,
            collateral
        );
        assertEq(valueAfter, valueBefore * 2, "Value should double with price");
    }

    // ═══════════════════════════════════════════════
    //       SHARES VALUE CONVERSION
    // ═══════════════════════════════════════════════

    function test_getSharesValueInLoanToken_accuracy() external {
        uint256 posId = _openCorrelatedPosition(
            alice,
            INITIAL_COLLATERAL,
            STANDARD_LTV
        );

        LeveragePosition memory pos = fl.getUserLeveragePosition(alice, posId);
        Position memory morphoPos = fl.getMorphoPosition(
            pos.userProxy,
            correlatedMarket
        );

        uint256 flashLoan = _calcFlashLoan(
            STANDARD_LTV,
            INITIAL_COLLATERAL,
            correlatedMarket
        );
        uint256 debtValue = fl.getSharesValueInLoanToken(
            correlatedMarket,
            morphoPos.borrowShares
        );

        // With zero interest IRM, debt should match flash loan exactly (± 1 wei rounding)
        assertApproxEqAbs(
            debtValue,
            flashLoan,
            1,
            "Debt should match flash loan with zero interest"
        );
    }

    function test_getSharesValueInLoanToken_zeroShares() external view {
        assertEq(fl.getSharesValueInLoanToken(correlatedMarket, 0), 0);
    }

    // ═══════════════════════════════════════════════
    //           MORPHO POSITION
    // ═══════════════════════════════════════════════

    function test_getMorphoPosition_afterLeverage() external {
        uint256 posId = _openCorrelatedPosition(
            alice,
            INITIAL_COLLATERAL,
            STANDARD_LTV
        );

        LeveragePosition memory pos = fl.getUserLeveragePosition(alice, posId);
        Position memory morphoPos = fl.getMorphoPosition(
            pos.userProxy,
            correlatedMarket
        );

        assertGt(morphoPos.collateral, 0);
        assertGt(morphoPos.borrowShares, 0);
    }

    function test_getMorphoPosition_afterSupply() external {
        uint256 posId = _openCorrelatedPosition(
            alice,
            INITIAL_COLLATERAL,
            STANDARD_LTV
        );
        LeveragePosition memory pos = fl.getUserLeveragePosition(alice, posId);

        Position memory morphoBefore = fl.getMorphoPosition(
            pos.userProxy,
            correlatedMarket
        );

        uint256 supplyAmount = 5e18;
        collateralToken.mint(alice, supplyAmount);
        vm.startPrank(alice);
        collateralToken.approve(address(fl), supplyAmount);
        fl.supplyCollateral(alice, posId, supplyAmount);
        vm.stopPrank();

        Position memory morphoAfter = fl.getMorphoPosition(
            pos.userProxy,
            correlatedMarket
        );
        assertEq(
            morphoAfter.collateral,
            morphoBefore.collateral + supplyAmount
        );
        assertEq(morphoAfter.borrowShares, morphoBefore.borrowShares);
    }

    function test_getMorphoPosition_afterBorrow() external {
        uint256 posId = _openCorrelatedPosition(
            alice,
            INITIAL_COLLATERAL,
            50e16
        );
        LeveragePosition memory pos = fl.getUserLeveragePosition(alice, posId);

        Position memory morphoBefore = fl.getMorphoPosition(
            pos.userProxy,
            correlatedMarket
        );

        uint256 borrowAmount = 1e17;
        vm.prank(alice);
        fl.borrow(posId, borrowAmount);

        Position memory morphoAfter = fl.getMorphoPosition(
            pos.userProxy,
            correlatedMarket
        );
        assertEq(
            morphoAfter.collateral,
            morphoBefore.collateral,
            "Collateral unchanged after borrow"
        );
        assertGt(
            morphoAfter.borrowShares,
            morphoBefore.borrowShares,
            "Debt increased after borrow"
        );
    }

    function test_getMorphoPosition_afterWithdraw() external {
        uint256 posId = _openCorrelatedPosition(
            alice,
            INITIAL_COLLATERAL,
            50e16
        );
        LeveragePosition memory pos = fl.getUserLeveragePosition(alice, posId);

        Position memory morphoBefore = fl.getMorphoPosition(
            pos.userProxy,
            correlatedMarket
        );

        uint256 withdrawAmount = morphoBefore.collateral / 10;
        vm.prank(alice);
        fl.withdrawCollateral(posId, withdrawAmount);

        Position memory morphoAfter = fl.getMorphoPosition(
            pos.userProxy,
            correlatedMarket
        );
        assertEq(
            morphoAfter.collateral,
            morphoBefore.collateral - withdrawAmount
        );
        assertEq(
            morphoAfter.borrowShares,
            morphoBefore.borrowShares,
            "Debt unchanged after withdraw"
        );
    }

    function test_getMorphoPosition_noPosition() external view {
        Position memory morphoPos = fl.getMorphoPosition(
            alice,
            correlatedMarket
        );
        assertEq(morphoPos.collateral, 0);
        assertEq(morphoPos.borrowShares, 0);
    }

    // ═══════════════════════════════════════════════
    //           LTV QUERIES
    // ═══════════════════════════════════════════════

    function test_getMaxLtv_correlated() external view {
        uint256 maxLtv = fl.getMaxLtv(correlatedMarket);
        assertEq(maxLtv, CORRELATED_LLTV - fl.LIQUIDATION_BUFFER());
    }

    function test_getMaxLtv_nonCorrelated() external view {
        uint256 maxLtv = fl.getMaxLtv(nonCorrelatedMarket);
        assertEq(maxLtv, NON_CORRELATED_LLTV - fl.LIQUIDATION_BUFFER());
    }

    function test_getLiqLtv() external view {
        assertEq(fl.getLiqLtv(correlatedMarket), CORRELATED_LLTV);
        assertEq(fl.getLiqLtv(nonCorrelatedMarket), NON_CORRELATED_LLTV);
    }

    // ═══════════════════════════════════════════════
    //           SWAP ROUTER / CONFIG QUERIES
    // ═══════════════════════════════════════════════

    function test_isValidSwapRouter() external {
        assertTrue(fl.isValidSwapRouter(address(router)));
        assertFalse(fl.isValidSwapRouter(makeAddr("random")));
    }

    function test_defaultFees() external view {
        assertEq(fl.s_yieldFee(), 10e16, "Default yield fee 10%");
        assertEq(fl.s_depositFee(), 1e16, "Default deposit fee 1%");
    }

    function test_treasury() external view {
        assertEq(fl.s_treasury(), treasury);
    }

    function test_morphoAddress() external view {
        assertEq(address(fl.i_morpho()), address(morpho));
    }

    function test_userProxyImplementation() external view {
        assertTrue(fl.i_userProxyImplementation() != address(0));
    }

    // ─── Internal helpers ───

    function _deleveragePosition(
        address user,
        uint256 posId,
        MarketParams memory mkt
    ) internal {
        LeveragePosition memory pos = fl.getUserLeveragePosition(user, posId);
        Position memory morphoPos = fl.getMorphoPosition(pos.userProxy, mkt);
        uint256 colVal = fl.getCollateralValueInLoanToken(
            mkt,
            morphoPos.collateral
        );
        SwapData memory swap = _buildSwapData(
            mkt.collateralToken,
            mkt.loanToken,
            morphoPos.collateral,
            colVal
        );

        vm.prank(user);
        fl.deleverage(posId, swap, 0);
    }
}
