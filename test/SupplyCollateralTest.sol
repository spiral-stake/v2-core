// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import "./TestBase.sol";
import {FLError} from "src/core/libraries/Error.sol";

/// @title SupplyCollateralTest
/// @notice Tests for FlashLeverage::supplyCollateral
contract SupplyCollateralTest is TestBase {
    function test_supplyCollateral_correlated_increasesDeposited() external {
        uint256 posId = _openCorrelatedPosition(alice, 10e18, 70e16);

        LeveragePosition memory posBefore = fl.getUserLeveragePosition(alice, posId);
        uint256 depositedBefore = posBefore.amountDepositedInLoanToken;

        uint256 supplyAmount = 5e18;
        collateralToken.mint(alice, supplyAmount);

        vm.startPrank(alice);
        collateralToken.approve(address(fl), supplyAmount);
        fl.supplyCollateral(alice, posId, supplyAmount);
        vm.stopPrank();

        LeveragePosition memory posAfter = fl.getUserLeveragePosition(alice, posId);
        assertGt(
            posAfter.amountDepositedInLoanToken,
            depositedBefore,
            "Deposited should increase after supply"
        );
    }

    function test_supplyCollateral_nonCorrelated_chargesDepositFee() external {
        uint256 posId = _openNonCorrelatedPosition(alice, 10e18, 50e16);

        uint256 supplyAmount = 5e18;
        ncCollateralToken.mint(alice, supplyAmount);

        uint256 treasuryBefore = ncCollateralToken.balanceOf(treasury);

        vm.startPrank(alice);
        ncCollateralToken.approve(address(fl), supplyAmount);
        fl.supplyCollateral(alice, posId, supplyAmount);
        vm.stopPrank();

        uint256 treasuryAfter = ncCollateralToken.balanceOf(treasury);
        assertGt(treasuryAfter, treasuryBefore, "Should charge deposit fee");
    }

    function test_supplyCollateral_correlated_noDepositFee() external {
        uint256 posId = _openCorrelatedPosition(alice, 10e18, 70e16);

        uint256 supplyAmount = 5e18;
        collateralToken.mint(alice, supplyAmount);

        uint256 treasuryBefore = collateralToken.balanceOf(treasury);

        vm.startPrank(alice);
        collateralToken.approve(address(fl), supplyAmount);
        fl.supplyCollateral(alice, posId, supplyAmount);
        vm.stopPrank();

        uint256 treasuryAfter = collateralToken.balanceOf(treasury);
        assertEq(treasuryAfter, treasuryBefore, "No deposit fee for correlated");
    }

    function test_supplyCollateral_reducesLTV() external {
        uint256 posId = _openCorrelatedPosition(alice, 10e18, 80e16);

        LeveragePosition memory pos = fl.getUserLeveragePosition(alice, posId);
        Position memory morphoBefore = fl.getMorphoPosition(pos.userProxy, correlatedMarket);

        uint256 supplyAmount = 10e18;
        collateralToken.mint(alice, supplyAmount);

        vm.startPrank(alice);
        collateralToken.approve(address(fl), supplyAmount);
        fl.supplyCollateral(alice, posId, supplyAmount);
        vm.stopPrank();

        Position memory morphoAfter = fl.getMorphoPosition(pos.userProxy, correlatedMarket);
        assertGt(morphoAfter.collateral, morphoBefore.collateral, "Collateral should increase");
        assertEq(morphoAfter.borrowShares, morphoBefore.borrowShares, "Debt should not change");
    }

    function test_supplyCollateral_revertsOnClosedPosition() external {
        uint256 posId = _openCorrelatedPosition(alice, 10e18, 70e16);

        // Close position
        LeveragePosition memory pos = fl.getUserLeveragePosition(alice, posId);
        Position memory morphoPos = fl.getMorphoPosition(pos.userProxy, correlatedMarket);
        uint256 colVal = fl.getCollateralValueInLoanToken(correlatedMarket, morphoPos.collateral);
        SwapData memory swap = _buildSwapData(
            address(collateralToken), address(loanToken), morphoPos.collateral, colVal
        );
        vm.prank(alice);
        fl.deleverage(posId, swap, 0);

        collateralToken.mint(alice, 5e18);
        vm.startPrank(alice);
        collateralToken.approve(address(fl), 5e18);
        vm.expectRevert(FLError.FlashLeverage__PositionAlreadyClosed.selector);
        fl.supplyCollateral(alice, posId, 5e18);
        vm.stopPrank();
    }

    function test_supplyCollateral_revertsOnZeroAmount() external {
        _openCorrelatedPosition(alice, 10e18, 70e16);

        vm.expectRevert(FLError.FlashLeverage__AmountCannotBeZero.selector);
        fl.supplyCollateral(alice, 0, 0);
    }
}
