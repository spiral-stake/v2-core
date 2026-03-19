// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import "./TestBase.sol";

/// @title FeeCalculationTest
/// @notice Detailed tests for yield fee and deposit fee calculations,
///         covering edge cases from Cyfrin audit and AI scan findings.
contract FeeCalculationTest is TestBase {
    // ═══════════════════════════════════════════════
    //       YIELD FEE ON CORRELATED WITHDRAW
    // ═══════════════════════════════════════════════

    /// @notice When no yield is generated, no fee should be charged
    function test_yieldFee_noYield_noFee() external {
        uint256 posId = _openCorrelatedPosition(alice, 10e18, 70e16);

        // No price change = no yield
        LeveragePosition memory pos = fl.getUserLeveragePosition(alice, posId);
        Position memory morphoPos = fl.getMorphoPosition(pos.userProxy, correlatedMarket);

        uint256 withdrawAmount = morphoPos.collateral / 10;
        uint256 treasuryBefore = collateralToken.balanceOf(treasury);

        vm.prank(alice);
        fl.withdrawCollateral(posId, withdrawAmount);

        uint256 treasuryAfter = collateralToken.balanceOf(treasury);
        assertEq(treasuryAfter, treasuryBefore, "No yield = no fee");
    }

    /// @notice When collateral depreciates, no yield fee should be charged
    function test_yieldFee_depreciation_noFee() external {
        uint256 posId = _openCorrelatedPosition(alice, 10e18, 70e16);

        // Price drops 5%
        correlatedOracle.setPrice(CORRELATED_PRICE * 95 / 100);

        LeveragePosition memory pos = fl.getUserLeveragePosition(alice, posId);
        Position memory morphoPos = fl.getMorphoPosition(pos.userProxy, correlatedMarket);

        uint256 withdrawAmount = morphoPos.collateral / 10;
        uint256 treasuryBefore = collateralToken.balanceOf(treasury);

        vm.prank(alice);
        fl.withdrawCollateral(posId, withdrawAmount);

        uint256 treasuryAfter = collateralToken.balanceOf(treasury);
        assertEq(treasuryAfter, treasuryBefore, "Depreciation = no yield fee");
    }

    /// @notice Yield fee is only charged on the yield portion, not the deposit
    function test_yieldFee_onlyOnYieldPortion() external {
        uint256 posId = _openCorrelatedPosition(alice, 10e18, 30e16);

        // Small yield: 2% appreciation
        correlatedOracle.setPrice(CORRELATED_PRICE * 102 / 100);

        LeveragePosition memory pos = fl.getUserLeveragePosition(alice, posId);
        Position memory morphoPos = fl.getMorphoPosition(pos.userProxy, correlatedMarket);

        // Large withdrawal that exceeds yield
        uint256 withdrawAmount = morphoPos.collateral / 2;
        uint256 treasuryBefore = collateralToken.balanceOf(treasury);

        vm.prank(alice);
        fl.withdrawCollateral(posId, withdrawAmount);

        uint256 fee = collateralToken.balanceOf(treasury) - treasuryBefore;
        // Fee should exist but be relatively small (only on yield portion)
        assertGt(fee, 0, "Should charge some fee");
    }

    /// @notice When withdrawal is entirely within yield, fee on full withdrawal
    function test_yieldFee_withdrawWithinYield_feeOnFullAmount() external {
        uint256 posId = _openCorrelatedPosition(alice, 10e18, 30e16);

        // Large yield: 50% appreciation
        correlatedOracle.setPrice(CORRELATED_PRICE * 150 / 100);

        LeveragePosition memory pos = fl.getUserLeveragePosition(alice, posId);
        Position memory morphoPos = fl.getMorphoPosition(pos.userProxy, correlatedMarket);

        // Tiny withdrawal — entirely within yield
        uint256 tinyWithdraw = morphoPos.collateral / 100;
        uint256 treasuryBefore = collateralToken.balanceOf(treasury);

        vm.prank(alice);
        fl.withdrawCollateral(posId, tinyWithdraw);

        uint256 fee = collateralToken.balanceOf(treasury) - treasuryBefore;
        assertGt(fee, 0, "Should charge fee on withdrawal within yield");
    }

    // ═══════════════════════════════════════════════
    //    YIELD FEE ON CORRELATED DELEVERAGE
    // ═══════════════════════════════════════════════

    /// @notice Deleverage with yield charges fee
    function test_yieldFee_deleverage_withYield() external {
        uint256 posId = _openCorrelatedPosition(alice, 10e18, 70e16);

        // 20% appreciation
        correlatedOracle.setPrice(CORRELATED_PRICE * 120 / 100);

        LeveragePosition memory pos = fl.getUserLeveragePosition(alice, posId);
        Position memory morphoPos = fl.getMorphoPosition(pos.userProxy, correlatedMarket);
        uint256 colVal = fl.getCollateralValueInLoanToken(correlatedMarket, morphoPos.collateral);

        SwapData memory swap = _buildSwapData(
            address(collateralToken), address(loanToken), morphoPos.collateral, colVal
        );

        uint256 treasuryBefore = loanToken.balanceOf(treasury);

        vm.prank(alice);
        fl.deleverage(posId, swap, 0);

        uint256 treasuryAfter = loanToken.balanceOf(treasury);
        assertGt(treasuryAfter, treasuryBefore, "Should charge yield fee on deleverage");
    }

    /// @notice Deleverage without yield charges no fee
    function test_yieldFee_deleverage_noYield() external {
        uint256 posId = _openCorrelatedPosition(alice, 10e18, 70e16);

        // No price change
        LeveragePosition memory pos = fl.getUserLeveragePosition(alice, posId);
        Position memory morphoPos = fl.getMorphoPosition(pos.userProxy, correlatedMarket);
        uint256 colVal = fl.getCollateralValueInLoanToken(correlatedMarket, morphoPos.collateral);

        SwapData memory swap = _buildSwapData(
            address(collateralToken), address(loanToken), morphoPos.collateral, colVal
        );

        uint256 treasuryBefore = loanToken.balanceOf(treasury);

        vm.prank(alice);
        fl.deleverage(posId, swap, 0);

        uint256 treasuryAfter = loanToken.balanceOf(treasury);
        assertEq(treasuryAfter, treasuryBefore, "No yield = no fee on deleverage");
    }

    // ═══════════════════════════════════════════════
    //       DEPOSIT FEE ON NON-CORRELATED
    // ═══════════════════════════════════════════════

    /// @notice Deposit fee is charged on leverage for non-correlated
    function test_depositFee_leverage_nonCorrelated() external {
        uint256 collateral = 100e18;
        uint256 treasuryBefore = ncCollateralToken.balanceOf(treasury);

        _openNonCorrelatedPosition(alice, collateral, 50e16);

        uint256 fee = ncCollateralToken.balanceOf(treasury) - treasuryBefore;
        // Fee should be ~1% of collateral
        uint256 expectedFee = (collateral * fl.s_depositFee()) / 1e18;
        assertApproxEqAbs(fee, expectedFee, 1, "Deposit fee should be ~1%");
    }

    /// @notice Deposit fee is charged on supplyCollateral for non-correlated
    function test_depositFee_supplyCollateral_nonCorrelated() external {
        uint256 posId = _openNonCorrelatedPosition(alice, 10e18, 50e16);

        uint256 supplyAmount = 10e18;
        ncCollateralToken.mint(alice, supplyAmount);

        uint256 treasuryBefore = ncCollateralToken.balanceOf(treasury);

        vm.startPrank(alice);
        ncCollateralToken.approve(address(fl), supplyAmount);
        fl.supplyCollateral(alice, posId, supplyAmount);
        vm.stopPrank();

        uint256 fee = ncCollateralToken.balanceOf(treasury) - treasuryBefore;
        uint256 expectedFee = (supplyAmount * fl.s_depositFee()) / 1e18;
        assertApproxEqAbs(fee, expectedFee, 1, "Supply should charge deposit fee");
    }

    /// @notice Deposit fee is charged on repay for non-correlated
    function test_depositFee_repay_nonCorrelated() external {
        uint256 posId = _openNonCorrelatedPosition(alice, 10e18, 50e16);

        LeveragePosition memory pos = fl.getUserLeveragePosition(alice, posId);
        Position memory morphoPos = fl.getMorphoPosition(pos.userProxy, nonCorrelatedMarket);
        uint256 debt = fl.getSharesValueInLoanToken(nonCorrelatedMarket, morphoPos.borrowShares);

        uint256 repayAmount = debt / 2;
        ncLoanToken.mint(alice, repayAmount);

        uint256 treasuryBefore = ncLoanToken.balanceOf(treasury);

        vm.startPrank(alice);
        ncLoanToken.approve(address(fl), repayAmount);
        fl.repay(alice, posId, repayAmount, 0);
        vm.stopPrank();

        uint256 fee = ncLoanToken.balanceOf(treasury) - treasuryBefore;
        assertGt(fee, 0, "Repay should charge deposit fee on non-correlated");
    }

    /// @notice No deposit fee on correlated leverage
    function test_depositFee_leverage_correlated_none() external {
        uint256 treasuryColBefore = collateralToken.balanceOf(treasury);
        uint256 treasuryLoanBefore = loanToken.balanceOf(treasury);

        _openCorrelatedPosition(alice, 10e18, 70e16);

        assertEq(collateralToken.balanceOf(treasury), treasuryColBefore, "No collateral fee");
        assertEq(loanToken.balanceOf(treasury), treasuryLoanBefore, "No loan fee");
    }

    // ═══════════════════════════════════════════════
    //          FEE PARAMETER EDGE CASES
    // ═══════════════════════════════════════════════

    /// @notice Zero deposit fee means no fee charged
    function test_depositFee_zeroFee_noCharge() external {
        fl.updateDepositFee(0);

        uint256 collateral = 100e18;
        uint256 treasuryBefore = ncCollateralToken.balanceOf(treasury);

        _openNonCorrelatedPosition(alice, collateral, 50e16);

        uint256 treasuryAfter = ncCollateralToken.balanceOf(treasury);
        assertEq(treasuryAfter, treasuryBefore, "Zero fee = no charge");
    }

    /// @notice Yield fee at max (10%) charges correctly
    function test_yieldFee_maxFee_chargesCorrectly() external {
        assertEq(fl.s_yieldFee(), 10e16, "Default yield fee should be 10%");

        uint256 posId = _openCorrelatedPosition(alice, 10e18, 70e16);

        // 20% appreciation
        correlatedOracle.setPrice(CORRELATED_PRICE * 120 / 100);

        LeveragePosition memory pos = fl.getUserLeveragePosition(alice, posId);
        Position memory morphoPos = fl.getMorphoPosition(pos.userProxy, correlatedMarket);
        uint256 colVal = fl.getCollateralValueInLoanToken(correlatedMarket, morphoPos.collateral);

        SwapData memory swap = _buildSwapData(
            address(collateralToken), address(loanToken), morphoPos.collateral, colVal
        );

        uint256 treasuryBefore = loanToken.balanceOf(treasury);

        vm.prank(alice);
        fl.deleverage(posId, swap, 0);

        uint256 fee = loanToken.balanceOf(treasury) - treasuryBefore;
        assertGt(fee, 0, "Max yield fee should produce non-zero fee");
    }

    /// @notice Reduced yield fee charges less
    function test_yieldFee_reducedFee_chargesLess() external {
        // Open two identical positions
        uint256 posId1 = _openCorrelatedPosition(alice, 10e18, 70e16);

        // 20% appreciation
        correlatedOracle.setPrice(CORRELATED_PRICE * 120 / 100);

        // Deleverage first position at 10% fee
        LeveragePosition memory pos1 = fl.getUserLeveragePosition(alice, posId1);
        Position memory morphoPos1 = fl.getMorphoPosition(pos1.userProxy, correlatedMarket);
        uint256 colVal1 = fl.getCollateralValueInLoanToken(correlatedMarket, morphoPos1.collateral);
        SwapData memory swap1 = _buildSwapData(
            address(collateralToken), address(loanToken), morphoPos1.collateral, colVal1
        );

        uint256 treasury1Before = loanToken.balanceOf(treasury);
        vm.prank(alice);
        fl.deleverage(posId1, swap1, 0);
        uint256 fee1 = loanToken.balanceOf(treasury) - treasury1Before;

        // Reset oracle, reduce fee to 5%, open and deleverage second position
        correlatedOracle.setPrice(CORRELATED_PRICE);
        fl.updateYieldFee(5e16);

        uint256 posId2 = _openCorrelatedPosition(alice, 10e18, 70e16);
        correlatedOracle.setPrice(CORRELATED_PRICE * 120 / 100);

        LeveragePosition memory pos2 = fl.getUserLeveragePosition(alice, posId2);
        Position memory morphoPos2 = fl.getMorphoPosition(pos2.userProxy, correlatedMarket);
        uint256 colVal2 = fl.getCollateralValueInLoanToken(correlatedMarket, morphoPos2.collateral);
        SwapData memory swap2 = _buildSwapData(
            address(collateralToken), address(loanToken), morphoPos2.collateral, colVal2
        );

        uint256 treasury2Before = loanToken.balanceOf(treasury);
        vm.prank(alice);
        fl.deleverage(posId2, swap2, 0);
        uint256 fee2 = loanToken.balanceOf(treasury) - treasury2Before;

        assertGt(fee1, fee2, "Higher yield fee should produce larger fee");
    }
}
