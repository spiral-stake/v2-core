// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import {FuzzTestBase} from "test/fuzz/FuzzTestBase.sol";
import {FLError} from "src/core/libraries/Error.sol";
import {Math} from "src/core/libraries/Math.sol";
import {LeveragePosition} from "src/core/structs/LeveragePosition.sol";
import {SwapData} from "src/core/structs/SwapData.sol";
import {MarketParams, Position} from "@morpho/interfaces/IMorpho.sol";

/// @notice Fuzz tests for supplyCollateral, borrow, repay, and withdrawCollateral.
contract FuzzPositionManagement is FuzzTestBase {
    using Math for uint256;

    uint256 constant MIN_COLLATERAL = 1e15;
    uint256 constant MAX_CORR_COLLATERAL = 50_000e18;
    uint256 constant MAX_NC_COLLATERAL = 50e18;
    uint256 constant MIN_LTV = 5e16;
    // Hardcoded because MAX_YIELD_FEE and MAX_DEPOSIT_FEE are private in FlashLeverage
    uint256 constant MAX_YIELD_FEE = 10e16;
    uint256 constant MAX_DEPOSIT_FEE = 1e16;

    // ─── supplyCollateral ──────────────────────────────────────────────────────

    function testFuzz_supplyCollateral_increasesAmountDeposited(
        uint256 collateral,
        uint256 extra
    ) external {
        collateral = bound(collateral, MIN_COLLATERAL, MAX_CORR_COLLATERAL);
        extra = bound(extra, MIN_COLLATERAL, MAX_CORR_COLLATERAL);

        uint256 posId = _openCorrelatedPosition(alice, collateral, 50e16);
        LeveragePosition memory posBefore = fl.getUserLeveragePosition(alice, posId);
        uint256 depositedBefore = posBefore.amountDepositedInLoanToken;

        collateralToken.mint(alice, extra);
        vm.startPrank(alice);
        collateralToken.approve(address(fl), extra);
        fl.supplyCollateral(alice, posId, extra);
        vm.stopPrank();

        LeveragePosition memory posAfter = fl.getUserLeveragePosition(alice, posId);
        uint256 extraInLoanToken = fl.getCollateralValueInLoanToken(correlatedMarket, extra);

        assertEq(
            posAfter.amountDepositedInLoanToken,
            depositedBefore + extraInLoanToken
        );
        assertEq(collateralToken.balanceOf(address(fl)), 0);
    }

    function testFuzz_supplyCollateral_closedPositionReverts(uint256 amount) external {
        amount = bound(amount, 1, 1e30);
        uint256 posId = _openCorrelatedPosition(alice, 10e18, 50e16);
        _deleveragePosition(alice, posId, correlatedMarket);

        collateralToken.mint(alice, amount);
        vm.startPrank(alice);
        collateralToken.approve(address(fl), amount);
        vm.expectRevert(FLError.FlashLeverage__PositionAlreadyClosed.selector);
        fl.supplyCollateral(alice, posId, amount);
        vm.stopPrank();
    }

    function testFuzz_supplyCollateral_zeroAmountReverts() external {
        uint256 posId = _openCorrelatedPosition(alice, 10e18, 50e16);

        vm.prank(alice);
        vm.expectRevert(FLError.FlashLeverage__AmountCannotBeZero.selector);
        fl.supplyCollateral(alice, posId, 0);
    }

    function testFuzz_supplyCollateral_depositFeeOnNonCorrelated(
        uint256 collateral,
        uint256 extra,
        uint256 feeSeed
    ) external {
        collateral = bound(collateral, MIN_COLLATERAL, MAX_NC_COLLATERAL / 2);
        extra = bound(extra, MIN_COLLATERAL, MAX_NC_COLLATERAL / 2);
        uint256 depositFee = bound(feeSeed, 1e14, MAX_DEPOSIT_FEE);
        fl.updateDepositFee(depositFee);

        uint256 posId = _openNonCorrelatedPosition(alice, collateral, 40e16);

        uint256 treasuryBefore = ncCollateralToken.balanceOf(treasury);
        ncCollateralToken.mint(alice, extra);
        vm.startPrank(alice);
        ncCollateralToken.approve(address(fl), extra);
        fl.supplyCollateral(alice, posId, extra);
        vm.stopPrank();

        uint256 fee = ncCollateralToken.balanceOf(treasury) - treasuryBefore;
        assertEq(fee, extra.mulDown(depositFee));
    }

    // ─── borrow ────────────────────────────────────────────────────────────────

    function testFuzz_borrow_closedPositionReverts(uint256 amount) external {
        amount = bound(amount, 1, 1e30);
        uint256 posId = _openCorrelatedPosition(alice, 10e18, 50e16);
        _deleveragePosition(alice, posId, correlatedMarket);

        vm.prank(alice);
        vm.expectRevert(FLError.FlashLeverage__PositionAlreadyClosed.selector);
        fl.borrow(posId, amount);
    }

    function testFuzz_borrow_zeroAmountReverts() external {
        uint256 posId = _openCorrelatedPosition(alice, 10e18, 50e16);
        vm.prank(alice);
        vm.expectRevert(FLError.FlashLeverage__AmountCannotBeZero.selector);
        fl.borrow(posId, 0);
    }

    function testFuzz_borrow_withinHeadroomSucceeds(uint256 collateral) external {
        // Open at a low LTV to guarantee headroom
        collateral = bound(collateral, 1e18, MAX_CORR_COLLATERAL);
        uint256 posId = _openCorrelatedPosition(alice, collateral, 30e16);

        LeveragePosition memory pos = fl.getUserLeveragePosition(alice, posId);
        Position memory morphoPos = fl.getMorphoPosition(pos.userProxy, correlatedMarket);

        // Compute safe borrow: stays well below maxLtv
        uint256 maxLtv = fl.getMaxLtv(correlatedMarket);
        uint256 collateralValue = fl.getCollateralValueInLoanToken(correlatedMarket, morphoPos.collateral);
        uint256 currentDebt = fl.getSharesValueInLoanToken(correlatedMarket, morphoPos.borrowShares);
        uint256 maxDebt = collateralValue.mulDown(maxLtv);
        uint256 headroom = maxDebt > currentDebt ? maxDebt - currentDebt : 0;
        vm.assume(headroom > 1e9);

        uint256 borrowAmount = headroom / 2; // Stay well within limit

        uint256 aliceBefore = loanToken.balanceOf(alice);
        vm.prank(alice);
        fl.borrow(posId, borrowAmount);

        assertEq(loanToken.balanceOf(alice), aliceBefore + borrowAmount);
        assertEq(loanToken.balanceOf(address(fl)), 0);
    }

    function testFuzz_borrow_exceedingLtvReverts(
        uint256 collateral,
        uint256 borrowExcess
    ) external {
        // Open very close to maxLtv so any additional borrow pushes over the limit
        collateral = bound(collateral, 1e18, 1_000e18);
        uint256 posId = _openCorrelatedPosition(alice, collateral, fl.getMaxLtv(correlatedMarket) - 1e14);

        LeveragePosition memory pos = fl.getUserLeveragePosition(alice, posId);
        Position memory morphoPos = fl.getMorphoPosition(pos.userProxy, correlatedMarket);

        uint256 maxLtv = fl.getMaxLtv(correlatedMarket);
        uint256 collateralValue = fl.getCollateralValueInLoanToken(correlatedMarket, morphoPos.collateral);
        uint256 currentDebt = fl.getSharesValueInLoanToken(correlatedMarket, morphoPos.borrowShares);
        uint256 maxDebt = collateralValue.mulDown(maxLtv);

        // Any amount above remaining headroom should push LTV past the limit
        uint256 tinyHeadroom = maxDebt > currentDebt ? maxDebt - currentDebt : 0;
        uint256 excessBorrow = tinyHeadroom + bound(borrowExcess, 1e15, 1_000e18);

        vm.prank(alice);
        vm.expectRevert();
        fl.borrow(posId, excessBorrow);
    }

    // Borrowing reduces amountDeposited for correlated markets
    function testFuzz_borrow_correlated_reducesDeposited(uint256 collateral) external {
        collateral = bound(collateral, 1e18, MAX_CORR_COLLATERAL);
        uint256 posId = _openCorrelatedPosition(alice, collateral, 30e16);

        LeveragePosition memory posBefore = fl.getUserLeveragePosition(alice, posId);
        uint256 depositedBefore = posBefore.amountDepositedInLoanToken;

        Position memory morphoPos = fl.getMorphoPosition(posBefore.userProxy, correlatedMarket);
        uint256 maxLtv = fl.getMaxLtv(correlatedMarket);
        uint256 collateralValue = fl.getCollateralValueInLoanToken(correlatedMarket, morphoPos.collateral);
        uint256 currentDebt = fl.getSharesValueInLoanToken(correlatedMarket, morphoPos.borrowShares);
        uint256 headroom = collateralValue.mulDown(maxLtv) - currentDebt;
        vm.assume(headroom > 1e9);

        uint256 borrowAmount = headroom / 2;
        uint256 borrowCapped = borrowAmount < depositedBefore ? borrowAmount : depositedBefore - 1;
        vm.assume(borrowCapped > 0);

        vm.prank(alice);
        fl.borrow(posId, borrowCapped);

        LeveragePosition memory posAfter = fl.getUserLeveragePosition(alice, posId);
        assertEq(posAfter.amountDepositedInLoanToken, depositedBefore - borrowCapped);
    }

    // ─── repay ─────────────────────────────────────────────────────────────────

    function testFuzz_repay_closedPositionReverts(uint256 amount) external {
        amount = bound(amount, 1, 1e30);
        uint256 posId = _openCorrelatedPosition(alice, 10e18, 50e16);
        _deleveragePosition(alice, posId, correlatedMarket);

        loanToken.mint(alice, amount);
        vm.startPrank(alice);
        loanToken.approve(address(fl), amount);
        vm.expectRevert(FLError.FlashLeverage__PositionAlreadyClosed.selector);
        fl.repay(alice, posId, amount, 0);
        vm.stopPrank();
    }

    function testFuzz_repay_excessRefunded(uint256 collateral, uint256 ltvSeed) external {
        collateral = bound(collateral, 1e18, MAX_CORR_COLLATERAL);
        uint256 maxLtv = fl.getMaxLtv(correlatedMarket);
        uint256 ltv = bound(ltvSeed, 30e16, maxLtv - 1e14);

        uint256 posId = _openCorrelatedPosition(alice, collateral, ltv);
        LeveragePosition memory pos = fl.getUserLeveragePosition(alice, posId);
        Position memory morphoPos = fl.getMorphoPosition(pos.userProxy, correlatedMarket);

        uint256 actualDebt = fl.getSharesValueInLoanToken(correlatedMarket, morphoPos.borrowShares);
        // Approve more than owed (1 WETH headroom). Full repayment uses the
        // supported borrowShares = type(uint256).max path, which repays exactly
        // the debt by shares and refunds any excess. (Repaying an over-debt
        // ASSET amount with borrowShares=0 is intentionally rejected by Morpho —
        // see test_poc_bug01_repayOverDebtPanics; callers use the max path.)
        uint256 overpay = actualDebt + 1e18;

        loanToken.mint(alice, overpay);
        uint256 aliceBefore = loanToken.balanceOf(alice);

        vm.startPrank(alice);
        loanToken.approve(address(fl), overpay);
        fl.repay(alice, posId, overpay, type(uint256).max);
        vm.stopPrank();

        // Alice should have gotten the excess back; net spend ≤ actualDebt + rounding
        uint256 spent = aliceBefore - loanToken.balanceOf(alice);
        assertLe(spent, actualDebt + 2, "Should not charge more than debt");
        assertEq(loanToken.balanceOf(address(fl)), 0);
    }

    function testFuzz_repay_fullRepayViaMaxShares(uint256 collateral, uint256 ltvSeed) external {
        collateral = bound(collateral, 1e18, MAX_CORR_COLLATERAL);
        uint256 maxLtv = fl.getMaxLtv(correlatedMarket);
        uint256 ltv = bound(ltvSeed, 30e16, maxLtv - 1e14);

        uint256 posId = _openCorrelatedPosition(alice, collateral, ltv);
        LeveragePosition memory pos = fl.getUserLeveragePosition(alice, posId);
        Position memory morphoPos = fl.getMorphoPosition(pos.userProxy, correlatedMarket);

        uint256 debt = fl.getSharesValueInLoanToken(correlatedMarket, morphoPos.borrowShares);

        loanToken.mint(alice, debt + 1e9); // small buffer for accrued interest
        vm.startPrank(alice);
        loanToken.approve(address(fl), debt + 1e9);
        // type(uint256).max signals "fetch shares from Morpho at call time"
        fl.repay(alice, posId, debt + 1e9, type(uint256).max);
        vm.stopPrank();

        // All borrow shares cleared
        Position memory morphoAfter = fl.getMorphoPosition(pos.userProxy, correlatedMarket);
        assertEq(morphoAfter.borrowShares, 0);
        assertEq(loanToken.balanceOf(address(fl)), 0);
    }

    function testFuzz_repay_increasesAmountDeposited(uint256 collateral, uint256 ltvSeed) external {
        collateral = bound(collateral, 1e18, MAX_CORR_COLLATERAL);
        uint256 maxLtv = fl.getMaxLtv(correlatedMarket);
        uint256 ltv = bound(ltvSeed, 30e16, maxLtv - 1e14);

        uint256 posId = _openCorrelatedPosition(alice, collateral, ltv);
        LeveragePosition memory posBefore = fl.getUserLeveragePosition(alice, posId);
        Position memory morphoPos = fl.getMorphoPosition(posBefore.userProxy, correlatedMarket);

        uint256 debt = fl.getSharesValueInLoanToken(correlatedMarket, morphoPos.borrowShares);
        uint256 partialRepay = debt / 2;
        vm.assume(partialRepay > 0);

        loanToken.mint(alice, partialRepay);
        vm.startPrank(alice);
        loanToken.approve(address(fl), partialRepay);
        fl.repay(alice, posId, partialRepay, 0);
        vm.stopPrank();

        LeveragePosition memory posAfter = fl.getUserLeveragePosition(alice, posId);
        // amountDepositedInLoanToken should increase by the repaid amount
        assertGe(posAfter.amountDepositedInLoanToken, posBefore.amountDepositedInLoanToken);
    }

    // ─── withdrawCollateral ────────────────────────────────────────────────────

    /// @notice After a partial deleverage (debt fully repaid, but only a fraction of
    ///         collateral withdrawn), the residual collateral stays in Morpho and MUST
    ///         be recoverable via withdrawCollateral even though position.open == false.
    /// WHY: withdrawCollateral intentionally has no position.open guard to support this
    ///      recovery path. Any stuck collateral left after a partial close is not lost.
    function testFuzz_withdrawCollateral_afterPartialDeleverage_recoversResidual(
        uint256 collateral,
        uint256 ltvSeed
    ) external {
        // Low LTV so partial collateral comfortably covers the debt
        collateral = bound(collateral, 2e18, MAX_CORR_COLLATERAL);
        uint256 ltv = bound(ltvSeed, MIN_LTV, 30e16);

        uint256 posId = _openCorrelatedPosition(alice, collateral, ltv);

        LeveragePosition memory pos = fl.getUserLeveragePosition(alice, posId);
        Position memory morphoPos = fl.getMorphoPosition(pos.userProxy, correlatedMarket);

        // Minimum collateral needed to swap at oracle price to cover the full debt
        uint256 debt = fl.getSharesValueInLoanToken(correlatedMarket, morphoPos.borrowShares);
        uint256 minCollateralToSwap = _calcSwapOutput(debt, correlatedMarket) + 1e12;

        // Skip if there would be no meaningful residual after the partial swap
        vm.assume(minCollateralToSwap < morphoPos.collateral);

        // Partial deleverage: repay ALL debt, withdraw only minCollateralToSwap
        SwapData memory swap = _buildSwapData(
            address(collateralToken), address(loanToken),
            minCollateralToSwap, debt + 1e12
        );

        vm.prank(alice);
        fl.deleverage(posId, minCollateralToSwap, swap, 0);

        // Debt fully repaid → position is closed
        assertFalse(fl.getUserLeveragePosition(alice, posId).open);

        // Residual collateral is still in Morpho under the proxy
        Position memory residualPos = fl.getMorphoPosition(pos.userProxy, correlatedMarket);
        assertGt(residualPos.collateral, 0);

        // User CAN withdraw the stuck collateral even though the position is closed
        uint256 aliceBefore = collateralToken.balanceOf(alice);
        vm.prank(alice);
        fl.withdrawCollateral(posId, residualPos.collateral);

        assertGt(collateralToken.balanceOf(alice) - aliceBefore, 0);
        assertEq(collateralToken.balanceOf(address(fl)), 0);
    }

    function testFuzz_withdrawCollateral_zeroAmountReverts() external {
        uint256 posId = _openCorrelatedPosition(alice, 10e18, 50e16);
        vm.prank(alice);
        vm.expectRevert(FLError.FlashLeverage__AmountCannotBeZero.selector);
        fl.withdrawCollateral(posId, 0);
    }

    function testFuzz_withdrawCollateral_smallFractionSucceeds(
        uint256 collateral,
        uint256 fractionBps
    ) external {
        // Open at low LTV to guarantee plenty of headroom for withdrawal
        collateral = bound(collateral, 1e18, MAX_CORR_COLLATERAL);
        uint256 posId = _openCorrelatedPosition(alice, collateral, 30e16);

        LeveragePosition memory pos = fl.getUserLeveragePosition(alice, posId);
        Position memory morphoPos = fl.getMorphoPosition(pos.userProxy, correlatedMarket);

        // Withdraw 0.01% to 5% of total collateral — safe at 30% opening LTV
        fractionBps = bound(fractionBps, 1, 500);
        uint256 withdrawAmount = (morphoPos.collateral * fractionBps) / 10000;
        vm.assume(withdrawAmount > 0);

        uint256 aliceBefore = collateralToken.balanceOf(alice);
        vm.prank(alice);
        fl.withdrawCollateral(posId, withdrawAmount);

        // Alice received at most the full withdrawal (minus any yield fee)
        uint256 aliceReceived = collateralToken.balanceOf(alice) - aliceBefore;
        assertLe(aliceReceived, withdrawAmount);
        assertGt(aliceReceived, 0);
        assertEq(collateralToken.balanceOf(address(fl)), 0);
    }

    function testFuzz_withdrawCollateral_exceedingLtvReverts(
        uint256 collateral,
        uint256 withdrawFractionBps
    ) external {
        // Open at high LTV so any significant withdrawal pushes past maxLtv
        collateral = bound(collateral, 1e18, 1_000e18);
        uint256 posId = _openCorrelatedPosition(alice, collateral, fl.getMaxLtv(correlatedMarket) - 1e14);

        LeveragePosition memory pos = fl.getUserLeveragePosition(alice, posId);
        Position memory morphoPos = fl.getMorphoPosition(pos.userProxy, correlatedMarket);

        // Withdrawing 20-100% of collateral at near-maxLtv must revert
        withdrawFractionBps = bound(withdrawFractionBps, 2000, 10000);
        uint256 withdrawAmount = (morphoPos.collateral * withdrawFractionBps) / 10000;
        vm.assume(withdrawAmount > 0);

        vm.prank(alice);
        vm.expectRevert();
        fl.withdrawCollateral(posId, withdrawAmount);
    }

    function testFuzz_withdrawCollateral_noYieldFeeOnNonCorrelated(
        uint256 collateral,
        uint256 fractionBps,
        uint256 priceBoost
    ) external {
        collateral = bound(collateral, MIN_COLLATERAL, MAX_NC_COLLATERAL);
        uint256 posId = _openNonCorrelatedPosition(alice, collateral, 30e16);

        // Simulate price appreciation — should still produce no yield fee for non-correlated
        priceBoost = bound(priceBoost, 100, 200); // 100% to 200% of original price
        nonCorrelatedOracle.setPrice((NON_CORRELATED_PRICE * priceBoost) / 100);

        LeveragePosition memory pos = fl.getUserLeveragePosition(alice, posId);
        Position memory morphoPos = fl.getMorphoPosition(pos.userProxy, nonCorrelatedMarket);

        // Withdraw a tiny fraction (safe at 30% LTV even after price changes)
        fractionBps = bound(fractionBps, 1, 100);
        uint256 withdrawAmount = (morphoPos.collateral * fractionBps) / 10000;
        vm.assume(withdrawAmount > 0);

        uint256 treasuryBefore = ncCollateralToken.balanceOf(treasury);
        vm.prank(alice);
        fl.withdrawCollateral(posId, withdrawAmount);

        assertEq(ncCollateralToken.balanceOf(treasury), treasuryBefore, "No yield fee on non-correlated");
        assertEq(ncCollateralToken.balanceOf(address(fl)), 0);
    }

    function testFuzz_withdrawCollateral_feeAndUserSumEqualsWithdrawal(
        uint256 collateral,
        uint256 priceBoost
    ) external {
        // Appreciation ensures yield fee is charged
        collateral = bound(collateral, 1e18, MAX_CORR_COLLATERAL);
        uint256 posId = _openCorrelatedPosition(alice, collateral, 30e16);

        priceBoost = bound(priceBoost, 110, 200); // 10–100% appreciation
        correlatedOracle.setPrice((CORRELATED_PRICE * priceBoost) / 100);

        LeveragePosition memory pos = fl.getUserLeveragePosition(alice, posId);
        Position memory morphoPos = fl.getMorphoPosition(pos.userProxy, correlatedMarket);

        uint256 withdrawAmount = morphoPos.collateral / 20; // 5% — safe for LTV
        vm.assume(withdrawAmount > 0);

        uint256 aliceBefore = collateralToken.balanceOf(alice);
        uint256 treasuryBefore = collateralToken.balanceOf(treasury);

        vm.prank(alice);
        fl.withdrawCollateral(posId, withdrawAmount);

        uint256 aliceReceived = collateralToken.balanceOf(alice) - aliceBefore;
        uint256 feeCharged = collateralToken.balanceOf(treasury) - treasuryBefore;

        // Fee + user received = total withdrawn
        assertEq(aliceReceived + feeCharged, withdrawAmount);
    }

    // ─── Internal helpers ──────────────────────────────────────────────────────

    function _deleveragePosition(address user, uint256 posId, MarketParams memory mkt) internal {
        LeveragePosition memory pos = fl.getUserLeveragePosition(user, posId);
        Position memory morphoPos = fl.getMorphoPosition(pos.userProxy, mkt);
        uint256 swapOut = fl.getCollateralValueInLoanToken(mkt, morphoPos.collateral) + 1e12;
        SwapData memory swap = _buildSwapData(
            mkt.collateralToken, mkt.loanToken, morphoPos.collateral, swapOut
        );
        vm.prank(user);
        fl.deleverage(posId, 0, swap, 0);
    }
}
