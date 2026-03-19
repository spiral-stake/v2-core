// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import "./TestBase.sol";

/// @title E2EFlowTest
/// @notice End-to-end lifecycle tests simulating realistic user journeys
contract E2EFlowTest is TestBase {
    /// @notice Full lifecycle: leverage → supply → borrow → repay → withdraw → deleverage
    function test_e2e_fullCorrelatedLifecycle() external {
        // 1. Open position
        uint256 posId = _openCorrelatedPosition(alice, 10e18, 70e16);

        LeveragePosition memory pos = fl.getUserLeveragePosition(alice, posId);
        assertTrue(pos.open);

        // 2. Supply additional collateral
        uint256 supplyAmount = 5e18;
        collateralToken.mint(alice, supplyAmount);
        vm.startPrank(alice);
        collateralToken.approve(address(fl), supplyAmount);
        fl.supplyCollateral(alice, posId, supplyAmount);
        vm.stopPrank();

        // 3. Borrow some loan tokens
        uint256 borrowAmount = 1e18;
        vm.prank(alice);
        fl.borrow(posId, borrowAmount);
        assertEq(loanToken.balanceOf(alice), borrowAmount);

        // 4. Repay the borrowed amount
        vm.startPrank(alice);
        loanToken.approve(address(fl), borrowAmount);
        fl.repay(alice, posId, borrowAmount, 0);
        vm.stopPrank();

        // 5. Withdraw some collateral
        pos = fl.getUserLeveragePosition(alice, posId);
        Position memory morphoPos = fl.getMorphoPosition(pos.userProxy, correlatedMarket);
        uint256 withdrawAmount = morphoPos.collateral / 10;
        vm.prank(alice);
        fl.withdrawCollateral(posId, withdrawAmount);

        // 6. Deleverage (close position)
        pos = fl.getUserLeveragePosition(alice, posId);
        morphoPos = fl.getMorphoPosition(pos.userProxy, correlatedMarket);
        uint256 colVal = fl.getCollateralValueInLoanToken(correlatedMarket, morphoPos.collateral);
        SwapData memory swap = _buildSwapData(
            address(collateralToken), address(loanToken), morphoPos.collateral, colVal
        );

        vm.prank(alice);
        uint256 returned = fl.deleverage(posId, swap, 0);

        pos = fl.getUserLeveragePosition(alice, posId);
        assertFalse(pos.open, "Position should be closed");
        assertGt(returned, 0, "Should return loan tokens");
    }

    /// @notice Correlated position with yield accrual and fee charging
    function test_e2e_correlatedWithYield() external {
        uint256 posId = _openCorrelatedPosition(alice, 10e18, 70e16);

        // Simulate 15% yield
        correlatedOracle.setPrice(CORRELATED_PRICE * 115 / 100);

        // Deleverage and check yield fee
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
        assertGt(treasuryAfter, treasuryBefore, "Treasury should receive yield fee");
    }

    /// @notice Non-correlated position with price appreciation
    function test_e2e_nonCorrelatedWithAppreciation() external {
        uint256 posId = _openNonCorrelatedPosition(alice, 10e18, 50e16);

        // Simulate 50% price appreciation
        nonCorrelatedOracle.setPrice(NON_CORRELATED_PRICE * 150 / 100);

        // Withdraw collateral — safe subtraction should handle it
        LeveragePosition memory pos = fl.getUserLeveragePosition(alice, posId);
        Position memory morphoPos = fl.getMorphoPosition(pos.userProxy, nonCorrelatedMarket);
        uint256 smallWithdraw = morphoPos.collateral / 10;

        vm.prank(alice);
        fl.withdrawCollateral(posId, smallWithdraw);

        // Borrow against appreciated collateral
        vm.prank(alice);
        fl.borrow(posId, 100e6); // borrow 100 USDC

        // Deleverage
        pos = fl.getUserLeveragePosition(alice, posId);
        morphoPos = fl.getMorphoPosition(pos.userProxy, nonCorrelatedMarket);
        uint256 colVal = fl.getCollateralValueInLoanToken(nonCorrelatedMarket, morphoPos.collateral);
        SwapData memory swap = _buildSwapData(
            address(ncCollateralToken), address(ncLoanToken), morphoPos.collateral, colVal
        );

        uint256 treasuryBefore = ncLoanToken.balanceOf(treasury);
        vm.prank(alice);
        fl.deleverage(posId, swap, 0);

        // No yield fee on non-correlated
        uint256 treasuryAfter = ncLoanToken.balanceOf(treasury);
        assertEq(treasuryAfter, treasuryBefore, "No yield fee on non-correlated deleverage");
    }

    /// @notice Repay all debt then withdraw all — tests the H-1 fix
    function test_e2e_repayAllThenWithdrawAll() external {
        uint256 posId = _openCorrelatedPosition(alice, 10e18, 70e16);

        // Simulate 5% yield
        correlatedOracle.setPrice(CORRELATED_PRICE * 105 / 100);

        // Fully repay debt
        LeveragePosition memory pos = fl.getUserLeveragePosition(alice, posId);
        Position memory morphoPos = fl.getMorphoPosition(pos.userProxy, correlatedMarket);
        uint256 debt = fl.getSharesValueInLoanToken(correlatedMarket, morphoPos.borrowShares);

        loanToken.mint(alice, debt);
        vm.startPrank(alice);
        loanToken.approve(address(fl), debt);
        fl.repay(alice, posId, debt, morphoPos.borrowShares);
        vm.stopPrank();

        // Withdraw all collateral — should NOT revert (H-1 fix)
        morphoPos = fl.getMorphoPosition(pos.userProxy, correlatedMarket);
        assertEq(morphoPos.borrowShares, 0, "Debt should be zero");

        vm.prank(alice);
        fl.withdrawCollateral(posId, morphoPos.collateral);

        // Alice should have all collateral back (minus yield fee)
        assertGt(collateralToken.balanceOf(alice), 0, "Alice should receive collateral");
    }

    /// @notice Increase leverage then deleverage
    function test_e2e_increaseLeverageThenClose() external {
        uint256 posId = _openCorrelatedPosition(alice, 10e18, 50e16);

        // Increase leverage
        uint256 additionalFlashLoan = 3e18;
        uint256 swapOut = _calcSwapOutput(additionalFlashLoan, correlatedMarket);
        SwapData memory incSwap = _buildSwapData(
            address(loanToken), address(collateralToken), additionalFlashLoan, swapOut
        );

        vm.prank(alice);
        fl.increaseLeverage(posId, additionalFlashLoan, incSwap, 0);

        // Verify position grew
        LeveragePosition memory pos = fl.getUserLeveragePosition(alice, posId);
        Position memory morphoPos = fl.getMorphoPosition(pos.userProxy, correlatedMarket);
        assertGt(morphoPos.collateral, 10e18, "Collateral should exceed initial deposit");

        // Deleverage
        uint256 colVal = fl.getCollateralValueInLoanToken(correlatedMarket, morphoPos.collateral);
        SwapData memory closeSwap = _buildSwapData(
            address(collateralToken), address(loanToken), morphoPos.collateral, colVal
        );

        vm.prank(alice);
        uint256 returned = fl.deleverage(posId, closeSwap, 0);

        assertGt(returned, 0, "Should return value to user");
        pos = fl.getUserLeveragePosition(alice, posId);
        assertFalse(pos.open, "Position should be closed");
    }

    /// @notice Multiple users on same market
    function test_e2e_multipleUsersIsolated() external {
        uint256 alicePosId = _openCorrelatedPosition(alice, 10e18, 70e16);
        uint256 bobPosId = _openCorrelatedPosition(bob, 20e18, 60e16);

        LeveragePosition memory alicePos = fl.getUserLeveragePosition(alice, alicePosId);
        LeveragePosition memory bobPos = fl.getUserLeveragePosition(bob, bobPosId);

        // Positions should have separate proxies
        assertTrue(alicePos.userProxy != bobPos.userProxy, "Proxies should be different");

        // Alice deleverages
        Position memory aliceMorpho = fl.getMorphoPosition(alicePos.userProxy, correlatedMarket);
        uint256 colVal = fl.getCollateralValueInLoanToken(correlatedMarket, aliceMorpho.collateral);
        SwapData memory swap = _buildSwapData(
            address(collateralToken), address(loanToken), aliceMorpho.collateral, colVal
        );
        vm.prank(alice);
        fl.deleverage(alicePosId, swap, 0);

        // Bob's position should be unaffected
        bobPos = fl.getUserLeveragePosition(bob, bobPosId);
        assertTrue(bobPos.open, "Bob's position should still be open");

        Position memory bobMorpho = fl.getMorphoPosition(bobPos.userProxy, correlatedMarket);
        assertGt(bobMorpho.collateral, 0, "Bob's collateral should be intact");
    }
}
