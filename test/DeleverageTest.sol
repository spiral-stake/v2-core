// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import "./TestBase.sol";
import {FLError} from "src/core/libraries/Error.sol";

/// @title DeleverageTest
/// @notice Tests for closing leveraged positions via FlashLeverage::deleverage
contract DeleverageTest is TestBase {
    // ─── Happy path ───

    function test_deleverage_correlated_closesPosition() external {
        uint256 posId = _openCorrelatedPosition(alice, 10e18, 70e16);

        LeveragePosition memory pos = fl.getUserLeveragePosition(alice, posId);
        Position memory morphoPos = fl.getMorphoPosition(pos.userProxy, correlatedMarket);

        // Build swap: collateral -> loan token
        uint256 collateralValue = fl.getCollateralValueInLoanToken(correlatedMarket, morphoPos.collateral);
        SwapData memory swap = _buildSwapData(
            address(collateralToken),
            address(loanToken),
            morphoPos.collateral,
            collateralValue
        );

        uint256 aliceLoanBefore = loanToken.balanceOf(alice);

        vm.prank(alice);
        uint256 returned = fl.deleverage(posId, swap, 0);

        assertGt(returned, 0, "Should return loan tokens to user");
        assertGt(loanToken.balanceOf(alice), aliceLoanBefore, "Alice should receive loan tokens");

        LeveragePosition memory posAfter = fl.getUserLeveragePosition(alice, posId);
        assertFalse(posAfter.open, "Position should be closed");
        assertGt(posAfter.amountReturnedInLoanToken, 0, "Return amount should be recorded");
    }

    function test_deleverage_correlated_chargesYieldFee() external {
        uint256 posId = _openCorrelatedPosition(alice, 10e18, 70e16);

        // Simulate yield: increase oracle price by 10%
        uint256 newPrice = CORRELATED_PRICE * 110 / 100;
        correlatedOracle.setPrice(newPrice);

        LeveragePosition memory pos = fl.getUserLeveragePosition(alice, posId);
        Position memory morphoPos = fl.getMorphoPosition(pos.userProxy, correlatedMarket);

        uint256 collateralValue = fl.getCollateralValueInLoanToken(correlatedMarket, morphoPos.collateral);
        SwapData memory swap = _buildSwapData(
            address(collateralToken),
            address(loanToken),
            morphoPos.collateral,
            collateralValue
        );

        uint256 treasuryBefore = loanToken.balanceOf(treasury);

        vm.prank(alice);
        fl.deleverage(posId, swap, 0);

        uint256 treasuryAfter = loanToken.balanceOf(treasury);
        assertGt(treasuryAfter, treasuryBefore, "Treasury should receive yield fee");
    }

    function test_deleverage_nonCorrelated_noYieldFee() external {
        uint256 posId = _openNonCorrelatedPosition(alice, 10e18, 50e16);

        // Simulate price appreciation
        nonCorrelatedOracle.setPrice(NON_CORRELATED_PRICE * 120 / 100);

        LeveragePosition memory pos = fl.getUserLeveragePosition(alice, posId);
        Position memory morphoPos = fl.getMorphoPosition(pos.userProxy, nonCorrelatedMarket);

        uint256 collateralValue = fl.getCollateralValueInLoanToken(nonCorrelatedMarket, morphoPos.collateral);
        SwapData memory swap = _buildSwapData(
            address(ncCollateralToken),
            address(ncLoanToken),
            morphoPos.collateral,
            collateralValue
        );

        uint256 treasuryBefore = ncLoanToken.balanceOf(treasury);

        vm.prank(alice);
        fl.deleverage(posId, swap, 0);

        uint256 treasuryAfter = ncLoanToken.balanceOf(treasury);
        assertEq(treasuryAfter, treasuryBefore, "No yield fee for non-correlated markets");
    }

    function test_deleverage_afterFullRepay_noDebt() external {
        uint256 posId = _openCorrelatedPosition(alice, 10e18, 70e16);

        // Fully repay debt
        LeveragePosition memory pos = fl.getUserLeveragePosition(alice, posId);
        Position memory morphoPos = fl.getMorphoPosition(pos.userProxy, correlatedMarket);
        uint256 debt = fl.getSharesValueInLoanToken(correlatedMarket, morphoPos.borrowShares);

        loanToken.mint(alice, debt);
        vm.startPrank(alice);
        loanToken.approve(address(fl), debt);
        fl.repay(alice, posId, debt, morphoPos.borrowShares);
        vm.stopPrank();

        // Deleverage with zero debt — should go through _handleDeleverage directly
        pos = fl.getUserLeveragePosition(alice, posId);
        morphoPos = fl.getMorphoPosition(pos.userProxy, correlatedMarket);
        assertEq(morphoPos.borrowShares, 0, "Debt should be zero");

        SwapData memory swap = _buildSwapData(
            address(collateralToken),
            address(loanToken),
            morphoPos.collateral,
            fl.getCollateralValueInLoanToken(correlatedMarket, morphoPos.collateral)
        );

        vm.prank(alice);
        fl.deleverage(posId, swap, 0);

        LeveragePosition memory posAfter = fl.getUserLeveragePosition(alice, posId);
        assertFalse(posAfter.open, "Position should be closed");
    }

    // ─── Revert cases ───

    function test_deleverage_revertsOnAlreadyClosed() external {
        uint256 posId = _openCorrelatedPosition(alice, 10e18, 70e16);

        // Close the position
        LeveragePosition memory pos = fl.getUserLeveragePosition(alice, posId);
        Position memory morphoPos = fl.getMorphoPosition(pos.userProxy, correlatedMarket);
        uint256 collateralValue = fl.getCollateralValueInLoanToken(correlatedMarket, morphoPos.collateral);
        SwapData memory swap = _buildSwapData(
            address(collateralToken), address(loanToken), morphoPos.collateral, collateralValue
        );

        vm.prank(alice);
        fl.deleverage(posId, swap, 0);

        // Try to close again
        vm.prank(alice);
        vm.expectRevert(FLError.FlashLeverage__PositionAlreadyClosed.selector);
        fl.deleverage(posId, swap, 0);
    }

    function test_deleverage_onlyOwnerCanClose() external {
        uint256 posId = _openCorrelatedPosition(alice, 10e18, 70e16);

        SwapData memory swap = SwapData({extRouter: address(router), extCalldata: ""});

        vm.prank(bob);
        vm.expectRevert(); // bob is not the position owner
        fl.deleverage(posId, swap, 0);
    }
}
