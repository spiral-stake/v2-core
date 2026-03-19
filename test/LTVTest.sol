// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import "./TestBase.sol";
import {FLError} from "src/core/libraries/Error.sol";

/// @title LTVTest
/// @notice Tests for LTV validation across leverage, borrow, withdraw operations
contract LTVTest is TestBase {
    // ═══════════════════════════════════════════════
    //             MAX LTV CALCULATION
    // ═══════════════════════════════════════════════

    function test_maxLtv_correlatedMarket() external view {
        uint256 maxLtv = fl.getMaxLtv(correlatedMarket);
        // LLTV (94.5%) - buffer (2.5%) = 92%
        assertEq(maxLtv, CORRELATED_LLTV - fl.LIQUIDATION_BUFFER());
    }

    function test_maxLtv_nonCorrelatedMarket() external view {
        uint256 maxLtv = fl.getMaxLtv(nonCorrelatedMarket);
        // LLTV (86%) - buffer (2.5%) = 83.5%
        assertEq(maxLtv, NON_CORRELATED_LLTV - fl.LIQUIDATION_BUFFER());
    }

    function test_liqLtv_returnsMarketLLTV() external view {
        assertEq(fl.getLiqLtv(correlatedMarket), CORRELATED_LLTV);
        assertEq(fl.getLiqLtv(nonCorrelatedMarket), NON_CORRELATED_LLTV);
    }

    // ═══════════════════════════════════════════════
    //        LEVERAGE LTV ENFORCEMENT
    // ═══════════════════════════════════════════════

    function test_leverage_atMaxLtv_succeeds() external {
        // Open at a high but valid LTV
        _openCorrelatedPosition(alice, 10e18, 89e16); // 89% < 92% max
        assertEq(fl.getUserLeveragePositions(alice).length, 1);
    }

    function test_leverage_aboveMaxLtv_reverts() external {
        uint256 collateral = 1e18;
        // Flash loan so large that even with swap output, LTV exceeds max
        uint256 flashLoan = 1000e18;

        uint256 swapOut = _calcSwapOutput(flashLoan, correlatedMarket);
        SwapData memory swap = _buildSwapData(
            address(loanToken),
            address(collateralToken),
            flashLoan,
            swapOut
        );

        collateralToken.mint(alice, collateral);
        vm.startPrank(alice);
        collateralToken.approve(address(fl), collateral);

        vm.expectRevert();
        fl.leverage(
            alice,
            LeverageParams({
                marketId: correlatedMarketId,
                amountCollateral: collateral,
                amountFlashLoan: flashLoan,
                swapData: swap,
                minTokenOut: 0
            })
        );
        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════
    //          BORROW LTV ENFORCEMENT
    // ═══════════════════════════════════════════════

    function test_borrow_withinLtv_succeeds() external {
        uint256 posId = _openCorrelatedPosition(alice, 10e18, 50e16);

        // Borrow a small amount within LTV
        vm.prank(alice);
        fl.borrow(posId, 1e18);

        assertGt(loanToken.balanceOf(alice), 0);
    }

    function test_borrow_exceedingLtv_reverts() external {
        uint256 posId = _openCorrelatedPosition(alice, 10e18, 85e16);

        // Try to borrow enough to exceed max LTV
        vm.prank(alice);
        vm.expectRevert(); // ExceedsMaxLTV
        fl.borrow(posId, 50e18);
    }

    // ═══════════════════════════════════════════════
    //       WITHDRAW LTV ENFORCEMENT
    // ═══════════════════════════════════════════════

    function test_withdraw_withinLtv_succeeds() external {
        uint256 posId = _openCorrelatedPosition(alice, 10e18, 50e16);

        LeveragePosition memory pos = fl.getUserLeveragePosition(alice, posId);
        Position memory morphoPos = fl.getMorphoPosition(
            pos.userProxy,
            correlatedMarket
        );

        // Withdraw a small amount
        uint256 smallWithdraw = morphoPos.collateral / 20;
        vm.prank(alice);
        fl.withdrawCollateral(posId, smallWithdraw);
    }

    function test_withdraw_exceedingLtv_reverts() external {
        uint256 posId = _openCorrelatedPosition(alice, 10e18, 85e16);

        LeveragePosition memory pos = fl.getUserLeveragePosition(alice, posId);
        Position memory morphoPos = fl.getMorphoPosition(
            pos.userProxy,
            correlatedMarket
        );

        // Try to withdraw most collateral — LTV would spike
        uint256 tooMuch = (morphoPos.collateral * 80) / 100;

        vm.prank(alice);
        vm.expectRevert(); // ExceedsMaxLTV
        fl.withdrawCollateral(posId, tooMuch);
    }

    // ═══════════════════════════════════════════════
    //       ZERO COLLATERAL / ZERO DEBT (M-1 fix)
    // ═══════════════════════════════════════════════

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

    // ═══════════════════════════════════════════════
    //          INCREASE LEVERAGE LTV
    // ═══════════════════════════════════════════════

    function test_increaseLeverage_withinLtv_succeeds() external {
        uint256 posId = _openCorrelatedPosition(alice, 10e18, 50e16);

        uint256 additionalFlash = 1e18;
        uint256 swapOut = _calcSwapOutput(additionalFlash, correlatedMarket);
        SwapData memory swap = _buildSwapData(
            address(loanToken),
            address(collateralToken),
            additionalFlash,
            swapOut
        );

        vm.prank(alice);
        fl.increaseLeverage(posId, additionalFlash, swap, 0);
    }

    function test_increaseLeverage_exceedingLtv_reverts() external {
        uint256 posId = _openCorrelatedPosition(alice, 10e18, 85e16);

        uint256 hugeFlash = 200e18;
        uint256 swapOut = _calcSwapOutput(hugeFlash, correlatedMarket);
        SwapData memory swap = _buildSwapData(
            address(loanToken),
            address(collateralToken),
            hugeFlash,
            swapOut
        );

        vm.prank(alice);
        vm.expectRevert(); // ExceedsMaxLTV
        fl.increaseLeverage(posId, hugeFlash, swap, 0);
    }

    // ═══════════════════════════════════════════════
    //       LTV AFTER SUPPLY COLLATERAL
    // ═══════════════════════════════════════════════

    function test_supplyCollateral_reducesEffectiveLtv() external {
        uint256 posId = _openCorrelatedPosition(alice, 10e18, 80e16);

        // After supply, borrow that previously would revert should succeed
        uint256 supplyAmount = 20e18;
        collateralToken.mint(alice, supplyAmount);

        vm.startPrank(alice);
        collateralToken.approve(address(fl), supplyAmount);
        fl.supplyCollateral(alice, posId, supplyAmount);
        vm.stopPrank();

        // Now borrow should succeed with the extra headroom
        vm.prank(alice);
        fl.borrow(posId, 1e18);
    }
}
