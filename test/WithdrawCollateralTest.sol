// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import "./TestBase.sol";
import {FLError} from "src/core/libraries/Error.sol";

/// @title WithdrawCollateralTest
/// @notice Tests for FlashLeverage::withdrawCollateral including yield fee logic,
///         safe subtraction, and pre-withdrawal position snapshot fix.
contract WithdrawCollateralTest is TestBase {
    using Math for uint256;

    uint256 constant INITIAL_COLLATERAL = 10e18;
    uint256 constant STANDARD_LTV = 70e16; // 70%
    uint256 constant LOW_LTV = 50e16; // 50%

    // ─── Happy path ───

    function test_withdrawCollateral_correlated_fullVerification() external {
        uint256 posId = _openCorrelatedPosition(
            alice,
            INITIAL_COLLATERAL,
            LOW_LTV
        );

        LeveragePosition memory posBefore = fl.getUserLeveragePosition(
            alice,
            posId
        );
        Position memory morphoBefore = fl.getMorphoPosition(
            posBefore.userProxy,
            correlatedMarket
        );
        uint256 depositedBefore = posBefore.amountDepositedInLoanToken;
        uint256 aliceBefore = collateralToken.balanceOf(alice);

        uint256 withdrawAmount = morphoBefore.collateral / 10; // 10% — safe for LTV
        uint256 withdrawInLoanToken = fl.getCollateralValueInLoanToken(
            correlatedMarket,
            withdrawAmount
        );

        vm.prank(alice);
        fl.withdrawCollateral(posId, withdrawAmount);

        LeveragePosition memory posAfter = fl.getUserLeveragePosition(
            alice,
            posId
        );
        Position memory morphoAfter = fl.getMorphoPosition(
            posAfter.userProxy,
            correlatedMarket
        );

        // Morpho collateral delta
        assertEq(
            morphoAfter.collateral,
            morphoBefore.collateral - withdrawAmount,
            "Morpho collateral should decrease by exact withdrawal"
        );

        // Debt unchanged
        assertEq(
            morphoAfter.borrowShares,
            morphoBefore.borrowShares,
            "Debt should not change"
        );

        // Deposited delta — no yield, so full withdrawal value deducted
        assertEq(
            posAfter.amountDepositedInLoanToken,
            depositedBefore - withdrawInLoanToken,
            "Deposited should decrease by withdrawal value in loan token"
        );

        // Alice receives exact amount (no yield = no fee)
        assertEq(
            collateralToken.balanceOf(alice),
            aliceBefore + withdrawAmount,
            "Alice should receive exact withdrawal amount"
        );

        // No tokens left in contract
        assertEq(collateralToken.balanceOf(address(fl)), 0);
        assertEq(loanToken.balanceOf(address(fl)), 0);
    }

    function test_withdrawCollateral_nonCorrelated_fullVerification() external {
        uint256 posId = _openNonCorrelatedPosition(
            alice,
            INITIAL_COLLATERAL,
            40e16
        );

        LeveragePosition memory posBefore = fl.getUserLeveragePosition(
            alice,
            posId
        );
        Position memory morphoBefore = fl.getMorphoPosition(
            posBefore.userProxy,
            nonCorrelatedMarket
        );
        uint256 aliceBefore = ncCollateralToken.balanceOf(alice);

        uint256 withdrawAmount = morphoBefore.collateral / 10;

        vm.prank(alice);
        fl.withdrawCollateral(posId, withdrawAmount);

        Position memory morphoAfter = fl.getMorphoPosition(
            posBefore.userProxy,
            nonCorrelatedMarket
        );

        // No yield fee on non-correlated
        assertEq(
            ncCollateralToken.balanceOf(alice),
            aliceBefore + withdrawAmount,
            "Alice should receive full amount, no yield fee"
        );

        // Morpho collateral delta
        assertEq(
            morphoAfter.collateral,
            morphoBefore.collateral - withdrawAmount
        );

        // Debt unchanged
        assertEq(morphoAfter.borrowShares, morphoBefore.borrowShares);

        // Treasury untouched
        assertEq(
            ncCollateralToken.balanceOf(treasury),
            ncCollateralToken.balanceOf(treasury)
        );
    }

    // ─── Yield fee verification ───

    function test_withdrawCollateral_correlated_yieldFeeAccuracy() external {
        uint256 posId = _openCorrelatedPosition(
            alice,
            INITIAL_COLLATERAL,
            LOW_LTV
        );

        // 10% appreciation
        uint256 appreciationPct = 110;
        correlatedOracle.setPrice((CORRELATED_PRICE * appreciationPct) / 100);

        LeveragePosition memory pos = fl.getUserLeveragePosition(alice, posId);
        Position memory morphoPos = fl.getMorphoPosition(
            pos.userProxy,
            correlatedMarket
        );

        // Small withdrawal within LTV headroom
        uint256 withdrawAmount = morphoPos.collateral / 20;

        uint256 treasuryBefore = collateralToken.balanceOf(treasury);
        uint256 aliceBefore = collateralToken.balanceOf(alice);

        vm.prank(alice);
        fl.withdrawCollateral(posId, withdrawAmount);

        uint256 fee = collateralToken.balanceOf(treasury) - treasuryBefore;
        uint256 aliceReceived = collateralToken.balanceOf(alice) - aliceBefore;

        // Fee + received = original withdrawal
        assertEq(
            fee + aliceReceived,
            withdrawAmount,
            "Fee + received should equal withdrawal amount"
        );
        assertGt(fee, 0, "Should charge yield fee on appreciated position");
    }

    function test_withdrawCollateral_noYield_noFee() external {
        uint256 posId = _openCorrelatedPosition(
            alice,
            INITIAL_COLLATERAL,
            LOW_LTV
        );

        // No price change = no yield
        LeveragePosition memory pos = fl.getUserLeveragePosition(alice, posId);
        Position memory morphoPos = fl.getMorphoPosition(
            pos.userProxy,
            correlatedMarket
        );

        uint256 withdrawAmount = morphoPos.collateral / 10;
        uint256 treasuryBefore = collateralToken.balanceOf(treasury);

        vm.prank(alice);
        fl.withdrawCollateral(posId, withdrawAmount);

        assertEq(
            collateralToken.balanceOf(treasury),
            treasuryBefore,
            "No yield = no fee"
        );
    }

    function test_withdrawCollateral_depreciation_noFee() external {
        uint256 posId = _openCorrelatedPosition(
            alice,
            INITIAL_COLLATERAL,
            LOW_LTV
        );

        // 5% depreciation
        correlatedOracle.setPrice((CORRELATED_PRICE * 95) / 100);

        LeveragePosition memory pos = fl.getUserLeveragePosition(alice, posId);
        Position memory morphoPos = fl.getMorphoPosition(
            pos.userProxy,
            correlatedMarket
        );

        uint256 withdrawAmount = morphoPos.collateral / 10;
        uint256 treasuryBefore = collateralToken.balanceOf(treasury);

        vm.prank(alice);
        fl.withdrawCollateral(posId, withdrawAmount);

        assertEq(
            collateralToken.balanceOf(treasury),
            treasuryBefore,
            "Depreciation = no fee"
        );
    }

    function test_withdrawCollateral_nonCorrelated_noYieldFee() external {
        uint256 posId = _openNonCorrelatedPosition(
            alice,
            INITIAL_COLLATERAL,
            40e16
        );

        // 50% appreciation — should still have no yield fee
        nonCorrelatedOracle.setPrice((NON_CORRELATED_PRICE * 150) / 100);

        LeveragePosition memory pos = fl.getUserLeveragePosition(alice, posId);
        Position memory morphoPos = fl.getMorphoPosition(
            pos.userProxy,
            nonCorrelatedMarket
        );

        uint256 withdrawAmount = morphoPos.collateral / 20;
        uint256 treasuryBefore = ncCollateralToken.balanceOf(treasury);

        vm.prank(alice);
        fl.withdrawCollateral(posId, withdrawAmount);

        assertEq(
            ncCollateralToken.balanceOf(treasury),
            treasuryBefore,
            "No yield fee on non-correlated"
        );
    }

    // ─── Yield within withdrawal ───

    function test_withdrawCollateral_withinYield_depositedUnchanged() external {
        uint256 posId = _openCorrelatedPosition(
            alice,
            INITIAL_COLLATERAL,
            30e16
        );

        // Large appreciation so yield >> withdrawal
        correlatedOracle.setPrice((CORRELATED_PRICE * 150) / 100);

        LeveragePosition memory posBefore = fl.getUserLeveragePosition(
            alice,
            posId
        );
        Position memory morphoPos = fl.getMorphoPosition(
            posBefore.userProxy,
            correlatedMarket
        );

        // Tiny withdrawal entirely within yield
        uint256 withdrawAmount = morphoPos.collateral / 100;

        vm.prank(alice);
        fl.withdrawCollateral(posId, withdrawAmount);

        LeveragePosition memory posAfter = fl.getUserLeveragePosition(
            alice,
            posId
        );
        assertEq(
            posAfter.amountDepositedInLoanToken,
            posBefore.amountDepositedInLoanToken,
            "Deposited should not change when withdrawing from yield only"
        );
    }

    // ─── Double-charge prevention (H-2 fix) ───

    function test_withdrawCollateral_noDoubleChargeOnPartialWithdrawals()
        external
    {
        uint256 posId = _openCorrelatedPosition(
            alice,
            INITIAL_COLLATERAL,
            LOW_LTV
        );

        // 10% yield
        correlatedOracle.setPrice((CORRELATED_PRICE * 110) / 100);

        LeveragePosition memory pos = fl.getUserLeveragePosition(alice, posId);
        Position memory morphoPos = fl.getMorphoPosition(
            pos.userProxy,
            correlatedMarket
        );

        uint256 withdrawAmount = morphoPos.collateral / 20; // 5% each

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

        assertLe(fee2, fee1, "Second withdrawal should not overcharge");
    }

    // ─── Safe subtraction (H-1 fix) ───

    function test_withdrawCollateral_safeSubtractionAfterAppreciation()
        external
    {
        uint256 posId = _openCorrelatedPosition(
            alice,
            INITIAL_COLLATERAL,
            STANDARD_LTV
        );

        // Fully repay debt
        _repayAllDebt(alice, posId, correlatedMarket);

        // 5% appreciation
        correlatedOracle.setPrice((CORRELATED_PRICE * 105) / 100);

        // Full withdrawal should NOT revert
        LeveragePosition memory pos = fl.getUserLeveragePosition(alice, posId);
        Position memory morphoPos = fl.getMorphoPosition(
            pos.userProxy,
            correlatedMarket
        );

        vm.prank(alice);
        fl.withdrawCollateral(posId, morphoPos.collateral);

        pos = fl.getUserLeveragePosition(alice, posId);
        assertEq(
            pos.amountDepositedInLoanToken,
            0,
            "Should clamp to 0, not underflow"
        );
    }

    function test_withdrawCollateral_nonCorrelated_safeSubtraction() external {
        uint256 posId = _openNonCorrelatedPosition(
            alice,
            INITIAL_COLLATERAL,
            40e16
        );

        // 100% price appreciation
        nonCorrelatedOracle.setPrice(NON_CORRELATED_PRICE * 2);

        LeveragePosition memory pos = fl.getUserLeveragePosition(alice, posId);
        Position memory morphoPos = fl.getMorphoPosition(
            pos.userProxy,
            nonCorrelatedMarket
        );

        uint256 withdrawAmount = morphoPos.collateral / 10;

        // Should NOT revert
        vm.prank(alice);
        fl.withdrawCollateral(posId, withdrawAmount);
    }

    // ─── Pre-withdrawal snapshot (AI scan fix) ───

    function test_withdrawCollateral_fullWithdrawalAfterRepay_chargesYieldFee()
        external
    {
        uint256 posId = _openCorrelatedPosition(
            alice,
            INITIAL_COLLATERAL,
            STANDARD_LTV
        );

        // Fully repay debt
        _repayAllDebt(alice, posId, correlatedMarket);

        // 10% yield
        correlatedOracle.setPrice((CORRELATED_PRICE * 110) / 100);

        LeveragePosition memory pos = fl.getUserLeveragePosition(alice, posId);
        Position memory morphoPos = fl.getMorphoPosition(
            pos.userProxy,
            correlatedMarket
        );

        uint256 treasuryBefore = collateralToken.balanceOf(treasury);

        vm.prank(alice);
        fl.withdrawCollateral(posId, morphoPos.collateral);

        assertGt(
            collateralToken.balanceOf(treasury),
            treasuryBefore,
            "Should charge yield fee on full withdrawal after repay"
        );
    }

    // ─── Multiple withdrawals ───

    function test_withdrawCollateral_multipleWithdrawalsAccumulate() external {
        uint256 posId = _openCorrelatedPosition(
            alice,
            INITIAL_COLLATERAL,
            30e16
        );
        uint256 withdrawCount = 3;

        LeveragePosition memory posStart = fl.getUserLeveragePosition(
            alice,
            posId
        );
        Position memory morphoStart = fl.getMorphoPosition(
            posStart.userProxy,
            correlatedMarket
        );
        uint256 depositedStart = posStart.amountDepositedInLoanToken;
        uint256 singleWithdraw = morphoStart.collateral / 20; // 5% each
        uint256 singleWithdrawInLoan = fl.getCollateralValueInLoanToken(
            correlatedMarket,
            singleWithdraw
        );

        for (uint256 i; i < withdrawCount; i++) {
            vm.prank(alice);
            fl.withdrawCollateral(posId, singleWithdraw);
        }

        LeveragePosition memory posEnd = fl.getUserLeveragePosition(
            alice,
            posId
        );
        Position memory morphoEnd = fl.getMorphoPosition(
            posEnd.userProxy,
            correlatedMarket
        );

        assertEq(
            morphoEnd.collateral,
            morphoStart.collateral - (singleWithdraw * withdrawCount),
            "Morpho collateral should decrease by total withdrawn"
        );

        // No yield = deposited decreases by total withdrawn value
        assertEq(
            posEnd.amountDepositedInLoanToken,
            depositedStart - (singleWithdrawInLoan * withdrawCount),
            "Deposited should decrease across multiple withdrawals"
        );
    }

    /// @notice Division by zero fix: when both collateral and debt are zero after full repay + withdraw
    function test_ltv_zeroCollateralZeroDebt_doesNotRevert() external {
        uint256 posId = _openCorrelatedPosition(alice, 10e18, 70e16);

        // Fully repay
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

        // Withdraw all — LTV check with 0/0 should not revert
        morphoPos = fl.getMorphoPosition(pos.userProxy, correlatedMarket);
        vm.prank(alice);
        fl.withdrawCollateral(posId, morphoPos.collateral);

        // Verify position is empty
        morphoPos = fl.getMorphoPosition(pos.userProxy, correlatedMarket);
        assertEq(morphoPos.collateral, 0);
        assertEq(morphoPos.borrowShares, 0);
    }

    // ─── Access control ───

    function test_withdrawCollateral_revertsOnNonOwner() external {
        uint256 posId = _openCorrelatedPosition(
            alice,
            INITIAL_COLLATERAL,
            LOW_LTV
        );

        vm.prank(bob);
        vm.expectRevert();
        fl.withdrawCollateral(posId, 1e18);
    }

    // ─── Revert cases ───

    function test_withdrawCollateral_revertsOnClosedPosition() external {
        uint256 posId = _openCorrelatedPosition(
            alice,
            INITIAL_COLLATERAL,
            STANDARD_LTV
        );
        _deleveragePosition(alice, posId, correlatedMarket);

        vm.prank(alice);
        vm.expectRevert(FLError.FlashLeverage__PositionAlreadyClosed.selector);
        fl.withdrawCollateral(posId, 1e18);
    }

    function test_withdrawCollateral_revertsOnZeroAmount() external {
        uint256 posId = _openCorrelatedPosition(
            alice,
            INITIAL_COLLATERAL,
            STANDARD_LTV
        );

        vm.prank(alice);
        vm.expectRevert(FLError.FlashLeverage__AmountCannotBeZero.selector);
        fl.withdrawCollateral(posId, 0);
    }

    function test_withdrawCollateral_revertsOnExceedingLTV() external {
        uint256 posId = _openCorrelatedPosition(
            alice,
            INITIAL_COLLATERAL,
            85e16
        );

        LeveragePosition memory pos = fl.getUserLeveragePosition(alice, posId);
        Position memory morphoPos = fl.getMorphoPosition(
            pos.userProxy,
            correlatedMarket
        );

        // Withdraw 80% of collateral — LTV would spike above max
        uint256 tooMuch = (morphoPos.collateral * 80) / 100;

        vm.prank(alice);
        vm.expectRevert();
        fl.withdrawCollateral(posId, tooMuch);
    }

    // ─── Internal helpers ───

    function _repayAllDebt(
        address user,
        uint256 posId,
        MarketParams memory mkt
    ) internal {
        LeveragePosition memory pos = fl.getUserLeveragePosition(user, posId);
        Position memory morphoPos = fl.getMorphoPosition(pos.userProxy, mkt);
        uint256 debt = fl.getSharesValueInLoanToken(
            mkt,
            morphoPos.borrowShares
        );

        MockERC20(mkt.loanToken).mint(user, debt);

        vm.startPrank(user);
        MockERC20(mkt.loanToken).approve(address(fl), debt);
        fl.repay(user, posId, debt, morphoPos.borrowShares);
        vm.stopPrank();
    }

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
        fl.deleverage(posId, 0, swap, 0);
    }
}
