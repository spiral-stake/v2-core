// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import "./TestBase.sol";
import {FLError} from "src/core/libraries/Error.sol";

/// @title WithdrawCollateralTest
/// @notice Tests for FlashLeverage::withdrawCollateral including yield fee calculation,
///         safe subtraction, and the pre-withdrawal position snapshot fix.
contract WithdrawCollateralTest is TestBase {
    // ─── Happy path ───

    function test_withdrawCollateral_partial() external {
        // Open at lower LTV so withdrawal has headroom
        uint256 posId = _openCorrelatedPosition(alice, 10e18, 50e16);

        LeveragePosition memory pos = fl.getUserLeveragePosition(alice, posId);
        Position memory morphoPos = fl.getMorphoPosition(
            pos.userProxy,
            correlatedMarket
        );
        uint256 totalCollateral = morphoPos.collateral;

        uint256 withdrawAmount = totalCollateral / 10; // withdraw 10%
        uint256 aliceBefore = collateralToken.balanceOf(alice);

        vm.prank(alice);
        fl.withdrawCollateral(posId, withdrawAmount);

        assertGt(
            collateralToken.balanceOf(alice),
            aliceBefore,
            "Alice should receive collateral"
        );
    }

    function test_withdrawCollateral_correlated_chargesYieldFee() external {
        uint256 posId = _openCorrelatedPosition(alice, 10e18, 70e16);

        // Simulate 10% appreciation (yield)
        correlatedOracle.setPrice((CORRELATED_PRICE * 110) / 100);

        LeveragePosition memory pos = fl.getUserLeveragePosition(alice, posId);
        Position memory morphoPos = fl.getMorphoPosition(
            pos.userProxy,
            correlatedMarket
        );

        // Withdraw a small amount (10% of collateral) to stay within LTV
        uint256 withdrawAmount = morphoPos.collateral / 10;
        uint256 treasuryBefore = collateralToken.balanceOf(treasury);

        vm.prank(alice);
        fl.withdrawCollateral(posId, withdrawAmount);

        uint256 treasuryAfter = collateralToken.balanceOf(treasury);
        assertGt(
            treasuryAfter,
            treasuryBefore,
            "Treasury should receive yield fee"
        );
    }

    function test_withdrawCollateral_nonCorrelated_noYieldFee() external {
        uint256 posId = _openNonCorrelatedPosition(alice, 10e18, 50e16);

        // Simulate price appreciation
        nonCorrelatedOracle.setPrice((NON_CORRELATED_PRICE * 150) / 100);

        LeveragePosition memory pos = fl.getUserLeveragePosition(alice, posId);
        Position memory morphoPos = fl.getMorphoPosition(
            pos.userProxy,
            nonCorrelatedMarket
        );

        uint256 withdrawAmount = morphoPos.collateral / 4;
        uint256 treasuryBefore = ncCollateralToken.balanceOf(treasury);

        vm.prank(alice);
        fl.withdrawCollateral(posId, withdrawAmount);

        uint256 treasuryAfter = ncCollateralToken.balanceOf(treasury);
        assertEq(
            treasuryAfter,
            treasuryBefore,
            "No yield fee for non-correlated"
        );
    }

    // ─── Double-charge prevention (H-2 fix) ───

    function test_withdrawCollateral_noDoubleChargeOnPartialWithdrawals()
        external
    {
        uint256 posId = _openCorrelatedPosition(alice, 10e18, 70e16);

        // Simulate 10% yield
        correlatedOracle.setPrice((CORRELATED_PRICE * 110) / 100);

        LeveragePosition memory pos = fl.getUserLeveragePosition(alice, posId);
        Position memory morphoPos = fl.getMorphoPosition(
            pos.userProxy,
            correlatedMarket
        );

        // Use small withdrawals (5% of collateral each)
        uint256 withdrawAmount = morphoPos.collateral / 20;

        // First withdrawal
        uint256 treasury1Before = collateralToken.balanceOf(treasury);
        vm.prank(alice);
        fl.withdrawCollateral(posId, withdrawAmount);
        uint256 fee1 = collateralToken.balanceOf(treasury) - treasury1Before;

        // Second withdrawal of same size
        uint256 treasury2Before = collateralToken.balanceOf(treasury);
        vm.prank(alice);
        fl.withdrawCollateral(posId, withdrawAmount);
        uint256 fee2 = collateralToken.balanceOf(treasury) - treasury2Before;

        // Fee on second withdrawal should be less than or equal to first
        assertLe(fee2, fee1, "Second withdrawal should not overcharge");
    }

    // ─── Safe subtraction (H-1 fix) ───

    function test_withdrawCollateral_safeSubtractionAfterAppreciation()
        external
    {
        uint256 posId = _openCorrelatedPosition(alice, 10e18, 70e16);

        // Fully repay debt
        LeveragePosition memory pos = fl.getUserLeveragePosition(alice, posId);
        Position memory morphoPos = fl.getMorphoPosition(
            pos.userProxy,
            correlatedMarket
        );
        uint256 debt = fl.getSharesValueInLoanToken(
            correlatedMarket,
            morphoPos.borrowShares
        );

        loanToken.mint(alice, debt);
        vm.startPrank(alice);
        loanToken.approve(address(fl), debt);
        fl.repay(alice, posId, debt, morphoPos.borrowShares);
        vm.stopPrank();

        // Simulate 5% appreciation
        correlatedOracle.setPrice((CORRELATED_PRICE * 105) / 100);

        // Should NOT revert due to underflow
        morphoPos = fl.getMorphoPosition(pos.userProxy, correlatedMarket);
        vm.prank(alice);
        fl.withdrawCollateral(posId, morphoPos.collateral);

        // Verify position deposited is zero (clamped, not underflowed)
        pos = fl.getUserLeveragePosition(alice, posId);
        assertEq(pos.amountDepositedInLoanToken, 0, "Should clamp to 0");
    }

    function test_withdrawCollateral_nonCorrelated_safeSubtraction() external {
        uint256 posId = _openNonCorrelatedPosition(alice, 10e18, 50e16);

        // Simulate 100% price appreciation
        nonCorrelatedOracle.setPrice(NON_CORRELATED_PRICE * 2);

        LeveragePosition memory pos = fl.getUserLeveragePosition(alice, posId);
        Position memory morphoPos = fl.getMorphoPosition(
            pos.userProxy,
            nonCorrelatedMarket
        );

        // Withdraw a small amount — value in loan token may exceed amountDeposited
        uint256 withdrawAmount = morphoPos.collateral / 4;

        // Should NOT revert
        vm.prank(alice);
        fl.withdrawCollateral(posId, withdrawAmount);
    }

    // ─── Pre-withdrawal snapshot (AI scan fix) ───

    function test_withdrawCollateral_fullWithdrawalAfterRepay_chargesYieldFee()
        external
    {
        uint256 posId = _openCorrelatedPosition(alice, 10e18, 70e16);

        // Fully repay debt
        LeveragePosition memory pos = fl.getUserLeveragePosition(alice, posId);
        Position memory morphoPos = fl.getMorphoPosition(
            pos.userProxy,
            correlatedMarket
        );
        uint256 debt = fl.getSharesValueInLoanToken(
            correlatedMarket,
            morphoPos.borrowShares
        );

        loanToken.mint(alice, debt);
        vm.startPrank(alice);
        loanToken.approve(address(fl), debt);
        fl.repay(alice, posId, debt, morphoPos.borrowShares);
        vm.stopPrank();

        // Simulate 10% yield
        correlatedOracle.setPrice((CORRELATED_PRICE * 110) / 100);

        // Full withdrawal should still charge yield fee
        morphoPos = fl.getMorphoPosition(pos.userProxy, correlatedMarket);
        uint256 treasuryBefore = collateralToken.balanceOf(treasury);

        vm.prank(alice);
        fl.withdrawCollateral(posId, morphoPos.collateral);

        uint256 treasuryAfter = collateralToken.balanceOf(treasury);
        assertGt(
            treasuryAfter,
            treasuryBefore,
            "Should charge yield fee on full withdrawal after repay"
        );
    }

    // ─── Yield within withdrawal ───

    function test_withdrawCollateral_yieldExceedsWithdrawal_noDepositedChange()
        external
    {
        uint256 posId = _openCorrelatedPosition(alice, 10e18, 30e16);

        // Simulate large appreciation so yield >> withdrawal
        correlatedOracle.setPrice((CORRELATED_PRICE * 150) / 100);

        LeveragePosition memory posBefore = fl.getUserLeveragePosition(
            alice,
            posId
        );
        uint256 depositedBefore = posBefore.amountDepositedInLoanToken;

        // Tiny withdrawal — within yield
        Position memory morphoPos = fl.getMorphoPosition(
            posBefore.userProxy,
            correlatedMarket
        );
        uint256 tinyWithdraw = morphoPos.collateral / 100;

        vm.prank(alice);
        fl.withdrawCollateral(posId, tinyWithdraw);

        LeveragePosition memory posAfter = fl.getUserLeveragePosition(
            alice,
            posId
        );
        // amountDepositedInLoanToken should not change when withdrawing from yield
        assertEq(
            posAfter.amountDepositedInLoanToken,
            depositedBefore,
            "Deposited should not change"
        );
    }

    // ─── Revert cases ───

    function test_withdrawCollateral_revertsOnClosedPosition() external {
        uint256 posId = _openCorrelatedPosition(alice, 10e18, 70e16);

        // Close position
        LeveragePosition memory pos = fl.getUserLeveragePosition(alice, posId);
        Position memory morphoPos = fl.getMorphoPosition(
            pos.userProxy,
            correlatedMarket
        );
        uint256 colVal = fl.getCollateralValueInLoanToken(
            correlatedMarket,
            morphoPos.collateral
        );
        SwapData memory swap = _buildSwapData(
            address(collateralToken),
            address(loanToken),
            morphoPos.collateral,
            colVal
        );
        vm.prank(alice);
        fl.deleverage(posId, swap, 0);

        vm.prank(alice);
        vm.expectRevert(FLError.FlashLeverage__PositionAlreadyClosed.selector);
        fl.withdrawCollateral(posId, 1e18);
    }

    function test_withdrawCollateral_revertsOnZeroAmount() external {
        _openCorrelatedPosition(alice, 10e18, 70e16);

        vm.prank(alice);
        vm.expectRevert(FLError.FlashLeverage__AmountCannotBeZero.selector);
        fl.withdrawCollateral(0, 0);
    }

    function test_withdrawCollateral_revertsOnExceedingLTV() external {
        uint256 posId = _openCorrelatedPosition(alice, 10e18, 90e16);

        LeveragePosition memory pos = fl.getUserLeveragePosition(alice, posId);
        Position memory morphoPos = fl.getMorphoPosition(
            pos.userProxy,
            correlatedMarket
        );

        // Try to withdraw most of collateral — should exceed LTV
        uint256 tooMuch = (morphoPos.collateral * 90) / 100;

        vm.prank(alice);
        vm.expectRevert();
        fl.withdrawCollateral(posId, tooMuch);
    }
}
