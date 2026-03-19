// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import "./TestBase.sol";

/// @title ViewFunctionTest
/// @notice Tests for view functions: isSupportedMarket, getUserLeveragePositions,
///         getCollateralValueInLoanToken, getSharesValueInLoanToken, getMorphoPosition
contract ViewFunctionTest is TestBase {
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

    function test_isCorrelated() external view {
        assertTrue(fl.s_isCorrelated(correlatedMarketId));
        assertFalse(fl.s_isCorrelated(nonCorrelatedMarketId));
    }

    // ═══════════════════════════════════════════════
    //          POSITION QUERIES
    // ═══════════════════════════════════════════════

    function test_getUserLeveragePositions_empty() external view {
        LeveragePosition[] memory positions = fl.getUserLeveragePositions(
            alice
        );
        assertEq(positions.length, 0);
    }

    function test_getUserLeveragePositions_afterOpen() external {
        _openCorrelatedPosition(alice, 10e18, 70e16);
        _openCorrelatedPosition(alice, 5e18, 60e16);

        LeveragePosition[] memory positions = fl.getUserLeveragePositions(
            alice
        );
        assertEq(positions.length, 2);
        assertTrue(positions[0].open);
        assertTrue(positions[1].open);
    }

    function test_getUserLeveragePosition_specific() external {
        _openCorrelatedPosition(alice, 10e18, 70e16);

        LeveragePosition memory pos = fl.getUserLeveragePosition(alice, 0);
        assertTrue(pos.open);
        assertEq(pos.marketId, correlatedMarketId);
        assertTrue(pos.userProxy != address(0));
        assertGt(pos.amountDepositedInLoanToken, 0);
    }

    // ═══════════════════════════════════════════════
    //       COLLATERAL VALUE CONVERSION
    // ═══════════════════════════════════════════════

    function test_getCollateralValueInLoanToken_correlated() external view {
        uint256 collateral = 10e18;
        uint256 value = fl.getCollateralValueInLoanToken(
            correlatedMarket,
            collateral
        );

        // 10 collateral * 1.1 price = 11 loan tokens (for 18-decimal pair)
        assertGt(value, 0, "Value should be non-zero");
    }

    function test_getCollateralValueInLoanToken_zero() external view {
        uint256 value = fl.getCollateralValueInLoanToken(correlatedMarket, 0);
        assertEq(value, 0, "Zero collateral = zero value");
    }

    function test_getCollateralValueInLoanToken_updatesWithOracle() external {
        uint256 collateral = 10e18;

        uint256 valueBefore = fl.getCollateralValueInLoanToken(
            correlatedMarket,
            collateral
        );

        // Double the oracle price
        correlatedOracle.setPrice(CORRELATED_PRICE * 2);

        uint256 valueAfter = fl.getCollateralValueInLoanToken(
            correlatedMarket,
            collateral
        );
        assertApproxEqAbs(
            valueAfter,
            valueBefore * 2,
            1,
            "Value should double with price"
        );
    }

    // ═══════════════════════════════════════════════
    //       SHARES VALUE CONVERSION
    // ═══════════════════════════════════════════════

    function test_getSharesValueInLoanToken_afterLeverage() external {
        uint256 posId = _openCorrelatedPosition(alice, 10e18, 70e16);

        LeveragePosition memory pos = fl.getUserLeveragePosition(alice, posId);
        Position memory morphoPos = fl.getMorphoPosition(
            pos.userProxy,
            correlatedMarket
        );

        uint256 debtValue = fl.getSharesValueInLoanToken(
            correlatedMarket,
            morphoPos.borrowShares
        );
        assertGt(debtValue, 0, "Debt value should be non-zero");
    }

    function test_getSharesValueInLoanToken_zeroShares() external view {
        uint256 value = fl.getSharesValueInLoanToken(correlatedMarket, 0);
        assertEq(value, 0, "Zero shares = zero value");
    }

    // ═══════════════════════════════════════════════
    //           MORPHO POSITION
    // ═══════════════════════════════════════════════

    function test_getMorphoPosition_afterLeverage() external {
        uint256 posId = _openCorrelatedPosition(alice, 10e18, 70e16);

        LeveragePosition memory pos = fl.getUserLeveragePosition(alice, posId);
        Position memory morphoPos = fl.getMorphoPosition(
            pos.userProxy,
            correlatedMarket
        );

        assertGt(morphoPos.collateral, 0, "Should have collateral");
        assertGt(morphoPos.borrowShares, 0, "Should have borrow shares");
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
    //           SWAP ROUTER QUERIES
    // ═══════════════════════════════════════════════

    function test_isValidSwapRouter_whitelisted() external view {
        assertTrue(fl.isValidSwapRouter(address(router)));
    }

    function test_isValidSwapRouter_notWhitelisted() external {
        assertFalse(fl.isValidSwapRouter(makeAddr("random")));
    }

    // ═══════════════════════════════════════════════
    //           FEE AND CONFIG QUERIES
    // ═══════════════════════════════════════════════

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
}
