// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import "./TestBase.sol";
import {FLError} from "src/core/libraries/Error.sol";

/// @title BorrowRepayTest
/// @notice Tests for FlashLeverage::borrow and FlashLeverage::repay
contract BorrowRepayTest is TestBase {
    using Math for uint256;

    uint256 constant INITIAL_COLLATERAL = 10e18;
    uint256 constant STANDARD_LTV = 70e16; // 70%

    // ═══════════════════════════════════════════════
    //                    BORROW
    // ═══════════════════════════════════════════════

    // ─── Happy path ───

    function test_borrow_correlated_fullVerification() external {
        uint256 posId = _openCorrelatedPosition(
            alice,
            INITIAL_COLLATERAL,
            50e16
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
        uint256 aliceBefore = loanToken.balanceOf(alice);

        uint256 borrowAmount = depositedBefore / 10; // 10% of deposited

        vm.prank(alice);
        fl.borrow(posId, borrowAmount);

        LeveragePosition memory posAfter = fl.getUserLeveragePosition(
            alice,
            posId
        );
        Position memory morphoAfter = fl.getMorphoPosition(
            posAfter.userProxy,
            correlatedMarket
        );

        // Exact tokens received
        assertEq(
            loanToken.balanceOf(alice),
            aliceBefore + borrowAmount,
            "Alice should receive exact borrow amount"
        );

        // Deposited delta accuracy
        assertEq(
            posAfter.amountDepositedInLoanToken,
            depositedBefore - borrowAmount,
            "Deposited should decrease by exact borrow amount"
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
            ) + borrowAmount,
            1,
            "Morpho debt should increase by borrow amount"
        );

        // Collateral unchanged
        assertEq(
            morphoAfter.collateral,
            morphoBefore.collateral,
            "Collateral should not change"
        );

        // No tokens left in contract
        assertEq(loanToken.balanceOf(address(fl)), 0);
        assertEq(collateralToken.balanceOf(address(fl)), 0);
    }

    function test_borrow_nonCorrelated_fullVerification() external {
        uint256 posId = _openNonCorrelatedPosition(
            alice,
            INITIAL_COLLATERAL,
            50e16
        );

        LeveragePosition memory posBefore = fl.getUserLeveragePosition(
            alice,
            posId
        );
        Position memory morphoBefore = fl.getMorphoPosition(
            posBefore.userProxy,
            nonCorrelatedMarket
        );
        uint256 depositedBefore = posBefore.amountDepositedInLoanToken;
        uint256 aliceBefore = ncLoanToken.balanceOf(alice);

        uint256 borrowAmount = 10e6; // 10 USDC

        vm.prank(alice);
        fl.borrow(posId, borrowAmount);

        LeveragePosition memory posAfter = fl.getUserLeveragePosition(
            alice,
            posId
        );
        Position memory morphoAfter = fl.getMorphoPosition(
            posAfter.userProxy,
            nonCorrelatedMarket
        );

        // Exact tokens received
        assertEq(
            ncLoanToken.balanceOf(alice),
            aliceBefore + borrowAmount,
            "Alice should receive exact borrow"
        );

        // Deposited decreases (non-correlated safe subtraction)
        assertEq(
            posAfter.amountDepositedInLoanToken,
            depositedBefore - borrowAmount,
            "Deposited should decrease by borrow amount"
        );

        // Collateral unchanged
        assertEq(
            morphoAfter.collateral,
            morphoBefore.collateral,
            "Collateral should not change"
        );

        // No fee on borrow
        assertEq(
            ncLoanToken.balanceOf(treasury),
            0,
            "No deposit fee on borrow"
        );
    }

    function test_borrow_multipleBorrowsAccumulate() external {
        uint256 posId = _openCorrelatedPosition(
            alice,
            INITIAL_COLLATERAL,
            30e16
        );
        uint256 borrowCount = 3;

        LeveragePosition memory posStart = fl.getUserLeveragePosition(
            alice,
            posId
        );
        uint256 depositedStart = posStart.amountDepositedInLoanToken;
        uint256 singleBorrow = depositedStart / 10; // 10% each time

        for (uint256 i; i < borrowCount; i++) {
            vm.prank(alice);
            fl.borrow(posId, singleBorrow);
        }

        LeveragePosition memory posEnd = fl.getUserLeveragePosition(
            alice,
            posId
        );
        assertEq(
            posEnd.amountDepositedInLoanToken,
            depositedStart - (singleBorrow * borrowCount),
            "Deposited should decrease across multiple borrows"
        );
        assertEq(
            loanToken.balanceOf(alice),
            singleBorrow * borrowCount,
            "Alice should receive total borrowed"
        );
    }

    // ─── Safe subtraction (non-correlated) ───

    function test_borrow_nonCorrelated_clampsDepositedToZeroOnAppreciation()
        external
    {
        uint256 posId = _openNonCorrelatedPosition(
            alice,
            INITIAL_COLLATERAL,
            50e16
        );

        // 2x price appreciation — lots of borrow headroom
        nonCorrelatedOracle.setPrice(NON_CORRELATED_PRICE * 2);

        LeveragePosition memory pos = fl.getUserLeveragePosition(alice, posId);
        uint256 deposited = pos.amountDepositedInLoanToken;

        // Borrow more than deposited — should clamp, not revert
        uint256 borrowAmount = deposited + 100e6;

        vm.prank(alice);
        fl.borrow(posId, borrowAmount);

        pos = fl.getUserLeveragePosition(alice, posId);
        assertEq(pos.amountDepositedInLoanToken, 0, "Should clamp to 0");
    }

    // ─── Correlated guard ───

    function test_borrow_correlated_revertsWhenExceedingDeposited() external {
        uint256 posId = _openCorrelatedPosition(
            alice,
            INITIAL_COLLATERAL,
            50e16
        );

        // 2x appreciation so LTV has headroom but deposited stays the same
        correlatedOracle.setPrice(CORRELATED_PRICE * 2);

        LeveragePosition memory pos = fl.getUserLeveragePosition(alice, posId);
        uint256 deposited = pos.amountDepositedInLoanToken;

        vm.prank(alice);
        vm.expectRevert(
            FLError
                .FlashLeverage__BorrowExceedsDepositedForCorrelatedPairs
                .selector
        );
        fl.borrow(posId, deposited + 1);
    }

    // ─── Revert cases ───

    function test_borrow_revertsOnClosedPosition() external {
        uint256 posId = _openCorrelatedPosition(
            alice,
            INITIAL_COLLATERAL,
            STANDARD_LTV
        );
        _deleveragePosition(alice, posId, correlatedMarket);

        vm.prank(alice);
        vm.expectRevert(FLError.FlashLeverage__PositionAlreadyClosed.selector);
        fl.borrow(posId, 1e18);
    }

    function test_borrow_revertsOnZeroAmount() external {
        uint256 posId = _openCorrelatedPosition(
            alice,
            INITIAL_COLLATERAL,
            STANDARD_LTV
        );

        vm.prank(alice);
        vm.expectRevert(FLError.FlashLeverage__AmountCannotBeZero.selector);
        fl.borrow(posId, 0);
    }

    function test_borrow_revertsOnExceedingLTV() external {
        uint256 posId = _openCorrelatedPosition(
            alice,
            INITIAL_COLLATERAL,
            80e16
        );

        vm.prank(alice);
        vm.expectRevert();
        fl.borrow(posId, 100e18);
    }

    function test_borrow_revertsOnNonOwner() external {
        uint256 posId = _openCorrelatedPosition(
            alice,
            INITIAL_COLLATERAL,
            50e16
        );

        vm.prank(bob);
        vm.expectRevert();
        fl.borrow(posId, 1e18);
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
