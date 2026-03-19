// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import "./TestBase.sol";
import {FLError} from "src/core/libraries/Error.sol";

/// @title BorrowRepayTest
/// @notice Tests for FlashLeverage::borrow and FlashLeverage::repay
contract BorrowRepayTest is TestBase {
    // ═══════════════════════════════════════════════
    //                    BORROW
    // ═══════════════════════════════════════════════

    function test_borrow_nonCorrelated_success() external {
        uint256 posId = _openNonCorrelatedPosition(alice, 10e18, 50e16);

        uint256 aliceBefore = ncLoanToken.balanceOf(alice);

        // Borrow a small amount
        uint256 borrowAmount = 10e6; // 10 USDC
        vm.prank(alice);
        fl.borrow(posId, borrowAmount);

        assertEq(
            ncLoanToken.balanceOf(alice) - aliceBefore,
            borrowAmount,
            "Should receive borrowed amount"
        );
    }

    function test_borrow_nonCorrelated_safeSubtractionOnAppreciation()
        external
    {
        uint256 posId = _openNonCorrelatedPosition(alice, 10e18, 50e16);

        // Simulate 100% price appreciation
        nonCorrelatedOracle.setPrice(NON_CORRELATED_PRICE * 2);

        LeveragePosition memory pos = fl.getUserLeveragePosition(alice, posId);
        uint256 deposited = pos.amountDepositedInLoanToken;

        // Borrow more than deposited — should NOT revert on non-correlated
        uint256 borrowAmount = deposited + 100e6;

        vm.prank(alice);
        fl.borrow(posId, borrowAmount);

        pos = fl.getUserLeveragePosition(alice, posId);
        assertEq(pos.amountDepositedInLoanToken, 0, "Should clamp to 0");
    }

    function test_borrow_correlated_withinDeposited() external {
        uint256 posId = _openCorrelatedPosition(alice, 10e18, 50e16);

        LeveragePosition memory pos = fl.getUserLeveragePosition(alice, posId);
        uint256 depositedBefore = pos.amountDepositedInLoanToken;

        uint256 borrowAmount = depositedBefore / 10; // 10% of deposited

        vm.prank(alice);
        fl.borrow(posId, borrowAmount);

        pos = fl.getUserLeveragePosition(alice, posId);
        assertEq(
            pos.amountDepositedInLoanToken,
            depositedBefore - borrowAmount,
            "Deposited should decrease by borrow amount"
        );
    }

    function test_borrow_correlated_revertsWhenExceedingDeposited() external {
        uint256 posId = _openCorrelatedPosition(alice, 10e18, 50e16);

        // Appreciate collateral so LTV drops and borrow headroom opens up
        correlatedOracle.setPrice((CORRELATED_PRICE * 200) / 100);

        LeveragePosition memory pos = fl.getUserLeveragePosition(alice, posId);
        uint256 deposited = pos.amountDepositedInLoanToken;

        // Now LTV is ~25% due to appreciation, so there's LTV headroom
        // But deposited hasn't changed, so borrowing deposited + 1 hits the correlated guard
        vm.prank(alice);
        vm.expectRevert(
            FLError
                .FlashLeverage__BorrowExceedsDepositedForCorrelatedPairs
                .selector
        );
        fl.borrow(posId, deposited + 1);
    }

    function test_borrow_revertsOnClosedPosition() external {
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
        fl.borrow(posId, 1e18);
    }

    function test_borrow_revertsOnZeroAmount() external {
        _openCorrelatedPosition(alice, 10e18, 70e16);

        vm.prank(alice);
        vm.expectRevert(FLError.FlashLeverage__AmountCannotBeZero.selector);
        fl.borrow(0, 0);
    }

    function test_borrow_revertsOnExceedingLTV() external {
        uint256 posId = _openCorrelatedPosition(alice, 10e18, 80e16);

        // Try to borrow a large amount that would exceed LTV
        vm.prank(alice);
        vm.expectRevert();
        fl.borrow(posId, 100e18);
    }

    // ═══════════════════════════════════════════════
    //                    REPAY
    // ═══════════════════════════════════════════════

    function test_repay_byAssets_success() external {
        uint256 posId = _openCorrelatedPosition(alice, 10e18, 70e16);

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

        uint256 depositedBefore = pos.amountDepositedInLoanToken;

        vm.startPrank(alice);
        loanToken.approve(address(fl), repayAmount);
        fl.repay(alice, posId, repayAmount, 0); // repay by assets
        vm.stopPrank();

        pos = fl.getUserLeveragePosition(alice, posId);
        assertGt(
            pos.amountDepositedInLoanToken,
            depositedBefore,
            "Deposited should increase after repay"
        );
    }

    function test_repay_byShares_usesActualRepaid() external {
        uint256 posId = _openCorrelatedPosition(alice, 10e18, 70e16);

        LeveragePosition memory pos = fl.getUserLeveragePosition(alice, posId);
        Position memory morphoPos = fl.getMorphoPosition(
            pos.userProxy,
            correlatedMarket
        );

        // Repay by shares with exact debt amount
        uint256 debt = fl.getSharesValueInLoanToken(
            correlatedMarket,
            morphoPos.borrowShares
        );
        loanToken.mint(alice, debt);

        uint256 depositedBefore = pos.amountDepositedInLoanToken;

        vm.startPrank(alice);
        loanToken.approve(address(fl), debt);
        fl.repay(alice, posId, debt, morphoPos.borrowShares);
        vm.stopPrank();

        pos = fl.getUserLeveragePosition(alice, posId);
        // amountDepositedInLoanToken should increase by actual repaid amount, not inflated input
        assertEq(
            pos.amountDepositedInLoanToken,
            depositedBefore + debt,
            "Should track actual repaid amount"
        );

        // Verify debt is fully cleared
        morphoPos = fl.getMorphoPosition(pos.userProxy, correlatedMarket);
        assertEq(morphoPos.borrowShares, 0, "Debt should be fully repaid");
    }

    function test_repay_fullDebt() external {
        uint256 posId = _openCorrelatedPosition(alice, 10e18, 70e16);

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

        morphoPos = fl.getMorphoPosition(pos.userProxy, correlatedMarket);
        assertEq(morphoPos.borrowShares, 0, "All debt should be repaid");
    }

    function test_repay_nonCorrelated_chargesDepositFee() external {
        uint256 posId = _openNonCorrelatedPosition(alice, 10e18, 50e16);

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

        uint256 treasuryBefore = ncLoanToken.balanceOf(treasury);

        vm.startPrank(alice);
        ncLoanToken.approve(address(fl), repayAmount);
        fl.repay(alice, posId, repayAmount, 0);
        vm.stopPrank();

        uint256 treasuryAfter = ncLoanToken.balanceOf(treasury);
        assertGt(
            treasuryAfter,
            treasuryBefore,
            "Should charge deposit fee on repay for non-correlated"
        );
    }

    function test_repay_revertsOnClosedPosition() external {
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

        loanToken.mint(alice, 1e18);
        vm.startPrank(alice);
        loanToken.approve(address(fl), 1e18);
        vm.expectRevert(FLError.FlashLeverage__PositionAlreadyClosed.selector);
        fl.repay(alice, posId, 1e18, 0);
        vm.stopPrank();
    }

    function test_repay_revertsOnZeroAmount() external {
        _openCorrelatedPosition(alice, 10e18, 70e16);

        vm.expectRevert(FLError.FlashLeverage__AmountCannotBeZero.selector);
        fl.repay(alice, 0, 0, 0);
    }
}
