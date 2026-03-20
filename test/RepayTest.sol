// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import "./TestBase.sol";
import {FLError} from "src/core/libraries/Error.sol";

/// @title RepayTest
/// @notice Tests for FlashLeverage::repay
contract RepayTest is TestBase {
    using Math for uint256;

    uint256 constant INITIAL_COLLATERAL = 10e18;
    uint256 constant STANDARD_LTV = 70e16; // 70%

    // ─── Happy path ───

    function test_repay_correlated_byAssets_fullVerification() external {
        uint256 posId = _openCorrelatedPosition(
            alice,
            INITIAL_COLLATERAL,
            STANDARD_LTV
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

        uint256 debt = fl.getSharesValueInLoanToken(
            correlatedMarket,
            morphoBefore.borrowShares
        );
        uint256 repayAmount = debt / 2;
        loanToken.mint(alice, repayAmount);

        uint256 aliceBefore = loanToken.balanceOf(alice);

        vm.startPrank(alice);
        loanToken.approve(address(fl), repayAmount);
        fl.repay(alice, posId, repayAmount, 0);
        vm.stopPrank();

        LeveragePosition memory posAfter = fl.getUserLeveragePosition(
            alice,
            posId
        );
        Position memory morphoAfter = fl.getMorphoPosition(
            posAfter.userProxy,
            correlatedMarket
        );

        // Deposited delta accuracy
        assertEq(
            posAfter.amountDepositedInLoanToken,
            depositedBefore + repayAmount,
            "Deposited should increase by exact repay amount"
        );

        // Morpho debt delta accuracy
        assertApproxEqAbs(
            fl.getSharesValueInLoanToken(
                correlatedMarket,
                morphoAfter.borrowShares
            ),
            fl.getSharesValueInLoanToken(
                correlatedMarket,
                morphoBefore.borrowShares
            ) - repayAmount,
            1,
            "Morpho debt should decrease by repay amount"
        );

        // Collateral unchanged
        assertEq(
            morphoAfter.collateral,
            morphoBefore.collateral,
            "Collateral should not change"
        );

        // Exact tokens pulled
        assertEq(
            loanToken.balanceOf(alice),
            aliceBefore - repayAmount,
            "Exact repay pulled from alice"
        );

        // No tokens left in contract
        assertEq(loanToken.balanceOf(address(fl)), 0);
        assertEq(collateralToken.balanceOf(address(fl)), 0);
    }

    function test_repay_byShares_usesActualRepaid() external {
        uint256 posId = _openCorrelatedPosition(
            alice,
            INITIAL_COLLATERAL,
            STANDARD_LTV
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

        uint256 debt = fl.getSharesValueInLoanToken(
            correlatedMarket,
            morphoBefore.borrowShares
        );
        loanToken.mint(alice, debt);

        vm.startPrank(alice);
        loanToken.approve(address(fl), debt);
        fl.repay(alice, posId, debt, morphoBefore.borrowShares);
        vm.stopPrank();

        LeveragePosition memory posAfter = fl.getUserLeveragePosition(
            alice,
            posId
        );
        Position memory morphoAfter = fl.getMorphoPosition(
            posAfter.userProxy,
            correlatedMarket
        );

        // Debt fully cleared
        assertEq(morphoAfter.borrowShares, 0, "Debt should be fully repaid");

        // Deposited tracks actual repaid, not inflated input
        assertEq(
            posAfter.amountDepositedInLoanToken,
            depositedBefore + debt,
            "Should track actual repaid amount"
        );
    }

    function test_repay_fullDebt_clearsAllShares() external {
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
        uint256 debt = fl.getSharesValueInLoanToken(
            correlatedMarket,
            morphoPos.borrowShares
        );

        _repayAsAlice(posId, debt, morphoPos.borrowShares, correlatedMarket);

        morphoPos = fl.getMorphoPosition(pos.userProxy, correlatedMarket);
        assertEq(morphoPos.borrowShares, 0, "All debt should be repaid");
        assertGt(morphoPos.collateral, 0, "Collateral should remain");
    }

    function test_repay_partialThenFull() external {
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
        uint256 totalDebt = fl.getSharesValueInLoanToken(
            correlatedMarket,
            morphoPos.borrowShares
        );

        // Partial repay — half the debt
        uint256 halfDebt = totalDebt / 2;
        _repayAsAlice(posId, halfDebt, 0, correlatedMarket);

        morphoPos = fl.getMorphoPosition(pos.userProxy, correlatedMarket);
        assertGt(
            morphoPos.borrowShares,
            0,
            "Should still have debt after partial repay"
        );

        // Full repay — remaining debt by shares
        uint256 remainingDebt = fl.getSharesValueInLoanToken(
            correlatedMarket,
            morphoPos.borrowShares
        );
        _repayAsAlice(
            posId,
            remainingDebt,
            morphoPos.borrowShares,
            correlatedMarket
        );

        morphoPos = fl.getMorphoPosition(pos.userProxy, correlatedMarket);
        assertEq(
            morphoPos.borrowShares,
            0,
            "Debt should be fully cleared after second repay"
        );
    }

    // ─── Fee verification ───

    function test_repay_nonCorrelated_exactDepositFee() external {
        uint256 posId = _openNonCorrelatedPosition(
            alice,
            INITIAL_COLLATERAL,
            50e16
        );

        LeveragePosition memory pos = fl.getUserLeveragePosition(alice, posId);
        Position memory morphoPos = fl.getMorphoPosition(
            pos.userProxy,
            nonCorrelatedMarket
        );
        uint256 debt = fl.getSharesValueInLoanToken(
            nonCorrelatedMarket,
            morphoPos.borrowShares
        );

        uint256 repayAmount = debt / 2;
        ncLoanToken.mint(alice, repayAmount);

        // Account for deposit fee already taken during leverage on collateral side
        // Repay fee is on loan token
        uint256 treasuryBefore = ncLoanToken.balanceOf(treasury);

        vm.startPrank(alice);
        ncLoanToken.approve(address(fl), repayAmount);
        fl.repay(alice, posId, repayAmount, 0);
        vm.stopPrank();

        uint256 fee = ncLoanToken.balanceOf(treasury) - treasuryBefore;
        assertEq(
            fee,
            repayAmount.mulDown(fl.s_depositFee()),
            "Fee should be exact depositFee percentage"
        );
    }

    function test_repay_correlated_noDepositFee() external {
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
        uint256 debt = fl.getSharesValueInLoanToken(
            correlatedMarket,
            morphoPos.borrowShares
        );

        uint256 repayAmount = debt / 2;
        loanToken.mint(alice, repayAmount);

        uint256 treasuryBefore = loanToken.balanceOf(treasury);

        vm.startPrank(alice);
        loanToken.approve(address(fl), repayAmount);
        fl.repay(alice, posId, repayAmount, 0);
        vm.stopPrank();

        assertEq(
            loanToken.balanceOf(treasury),
            treasuryBefore,
            "No deposit fee for correlated repay"
        );
    }

    // ─── Anyone can repay on behalf ───

    function test_repay_bobPaysForAlice() external {
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
        uint256 debt = fl.getSharesValueInLoanToken(
            correlatedMarket,
            morphoBefore.borrowShares
        );

        uint256 repayAmount = debt / 2;
        loanToken.mint(bob, repayAmount);

        uint256 aliceLoanBefore = loanToken.balanceOf(alice);
        uint256 bobLoanBefore = loanToken.balanceOf(bob);

        vm.startPrank(bob);
        loanToken.approve(address(fl), repayAmount);
        fl.repay(alice, posId, repayAmount, 0);
        vm.stopPrank();

        // Bob pays, alice untouched
        assertEq(
            loanToken.balanceOf(alice),
            aliceLoanBefore,
            "Alice balance should not change"
        );
        assertEq(
            loanToken.balanceOf(bob),
            bobLoanBefore - repayAmount,
            "Bob should pay"
        );

        // Debt reduced
        Position memory morphoAfter = fl.getMorphoPosition(
            pos.userProxy,
            correlatedMarket
        );
        assertLt(
            morphoAfter.borrowShares,
            morphoBefore.borrowShares,
            "Debt should decrease"
        );
    }

    // ─── Revert cases ───

    function test_repay_revertsOnClosedPosition() external {
        uint256 posId = _openCorrelatedPosition(
            alice,
            INITIAL_COLLATERAL,
            STANDARD_LTV
        );
        _deleveragePosition(alice, posId, correlatedMarket);

        loanToken.mint(alice, 1e18);
        vm.startPrank(alice);
        loanToken.approve(address(fl), 1e18);
        vm.expectRevert(FLError.FlashLeverage__PositionAlreadyClosed.selector);
        fl.repay(alice, posId, 1e18, 0);
        vm.stopPrank();
    }

    function test_repay_revertsOnZeroAmount() external {
        uint256 posId = _openCorrelatedPosition(
            alice,
            INITIAL_COLLATERAL,
            STANDARD_LTV
        );

        vm.expectRevert(FLError.FlashLeverage__AmountCannotBeZero.selector);
        fl.repay(alice, posId, 0, 0);
    }

    // ─── Internal helpers ───

    function _repayAsAlice(
        uint256 posId,
        uint256 amount,
        uint256 borrowShares,
        MarketParams memory mkt
    ) internal {
        MockERC20(mkt.loanToken).mint(alice, amount);

        vm.startPrank(alice);
        MockERC20(mkt.loanToken).approve(address(fl), amount);
        fl.repay(alice, posId, amount, borrowShares);
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
        fl.deleverage(posId, swap, 0);
    }
}
