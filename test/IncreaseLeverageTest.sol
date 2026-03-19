// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import "./TestBase.sol";
import {FLError} from "src/core/libraries/Error.sol";

/// @title IncreaseLeverageTest
/// @notice Tests for FlashLeverage::increaseLeverage
contract IncreaseLeverageTest is TestBase {
    function test_increaseLeverage_addsCollateralAndDebt() external {
        uint256 posId = _openCorrelatedPosition(alice, 10e18, 50e16);

        LeveragePosition memory posBefore = fl.getUserLeveragePosition(alice, posId);
        Position memory morphoBefore = fl.getMorphoPosition(posBefore.userProxy, correlatedMarket);

        uint256 additionalFlashLoan = 2e18;
        uint256 swapOut = _calcSwapOutput(additionalFlashLoan, correlatedMarket);
        SwapData memory swap = _buildSwapData(
            address(loanToken), address(collateralToken), additionalFlashLoan, swapOut
        );

        vm.prank(alice);
        fl.increaseLeverage(posId, additionalFlashLoan, swap, 0);

        Position memory morphoAfter = fl.getMorphoPosition(posBefore.userProxy, correlatedMarket);
        assertGt(morphoAfter.collateral, morphoBefore.collateral, "Collateral should increase");
        assertGt(morphoAfter.borrowShares, morphoBefore.borrowShares, "Debt should increase");
    }

    function test_increaseLeverage_doesNotChangeDeposited() external {
        uint256 posId = _openCorrelatedPosition(alice, 10e18, 50e16);

        LeveragePosition memory posBefore = fl.getUserLeveragePosition(alice, posId);
        uint256 depositedBefore = posBefore.amountDepositedInLoanToken;

        uint256 additionalFlashLoan = 2e18;
        uint256 swapOut = _calcSwapOutput(additionalFlashLoan, correlatedMarket);
        SwapData memory swap = _buildSwapData(
            address(loanToken), address(collateralToken), additionalFlashLoan, swapOut
        );

        vm.prank(alice);
        fl.increaseLeverage(posId, additionalFlashLoan, swap, 0);

        LeveragePosition memory posAfter = fl.getUserLeveragePosition(alice, posId);
        assertEq(
            posAfter.amountDepositedInLoanToken,
            depositedBefore,
            "amountDeposited should not change for increaseLeverage"
        );
    }

    function test_increaseLeverage_revertsOnClosedPosition() external {
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

        SwapData memory newSwap = SwapData({extRouter: address(router), extCalldata: ""});
        vm.prank(alice);
        vm.expectRevert(FLError.FlashLeverage__PositionAlreadyClosed.selector);
        fl.increaseLeverage(posId, 1e18, newSwap, 0);
    }

    function test_increaseLeverage_revertsOnZeroAmount() external {
        _openCorrelatedPosition(alice, 10e18, 70e16);

        SwapData memory swap = SwapData({extRouter: address(router), extCalldata: ""});
        vm.prank(alice);
        vm.expectRevert(FLError.FlashLeverage__AmountCannotBeZero.selector);
        fl.increaseLeverage(0, 0, swap, 0);
    }

    function test_increaseLeverage_revertsOnExceedingLTV() external {
        uint256 posId = _openCorrelatedPosition(alice, 10e18, 85e16);

        // Try to increase leverage by a lot — should exceed LTV
        uint256 hugeFlashLoan = 100e18;
        uint256 swapOut = _calcSwapOutput(hugeFlashLoan, correlatedMarket);
        SwapData memory swap = _buildSwapData(
            address(loanToken), address(collateralToken), hugeFlashLoan, swapOut
        );

        vm.prank(alice);
        vm.expectRevert();
        fl.increaseLeverage(posId, hugeFlashLoan, swap, 0);
    }

    function test_increaseLeverage_onlyOwnerCanCall() external {
        uint256 posId = _openCorrelatedPosition(alice, 10e18, 50e16);

        SwapData memory swap = SwapData({extRouter: address(router), extCalldata: ""});

        vm.prank(bob);
        vm.expectRevert(); // bob is not position owner
        fl.increaseLeverage(posId, 1e18, swap, 0);
    }
}
