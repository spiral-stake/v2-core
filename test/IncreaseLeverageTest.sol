// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import "./TestBase.sol";
import {FLError} from "src/core/libraries/Error.sol";

/// @title IncreaseLeverageTest
/// @notice Tests for FlashLeverage::increaseLeverage
contract IncreaseLeverageTest is TestBase {
    using Math for uint256;

    uint256 constant INITIAL_COLLATERAL = 10e18;
    uint256 constant STANDARD_LTV = 70e16; // 70%

    // ─── Happy path ───

    function test_increaseLeverage_fullVerification() external {
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

        uint256 flashLoan = 2e18;
        uint256 swapOut = _calcSwapOutput(flashLoan, correlatedMarket);
        SwapData memory swap = _buildSwapData(
            address(loanToken),
            address(collateralToken),
            flashLoan,
            swapOut
        );

        vm.prank(alice);
        fl.increaseLeverage(posId, flashLoan, swap, 0);

        LeveragePosition memory posAfter = fl.getUserLeveragePosition(
            alice,
            posId
        );
        Position memory morphoAfter = fl.getMorphoPosition(
            posAfter.userProxy,
            correlatedMarket
        );

        // Position struct unchanged
        assertTrue(posAfter.open);
        assertEq(posAfter.marketId, correlatedMarketId);
        assertEq(
            posAfter.userProxy,
            posBefore.userProxy,
            "Should reuse same proxy"
        );
        assertEq(
            posAfter.amountDepositedInLoanToken,
            posBefore.amountDepositedInLoanToken,
            "Deposited should not change"
        );
        assertEq(posAfter.amountReturnedInLoanToken, 0);

        // Morpho position delta accuracy
        assertEq(
            morphoAfter.collateral,
            morphoBefore.collateral + swapOut,
            "Collateral should increase by swap output"
        );
        assertApproxEqAbs(
            fl.getSharesValueInLoanToken(
                correlatedMarket,
                morphoAfter.borrowShares
            ),
            fl.getSharesValueInLoanToken(
                correlatedMarket,
                morphoBefore.borrowShares
            ) + flashLoan,
            1,
            "Debt should increase by flash loan amount"
        );

        // No tokens left in contract
        assertEq(collateralToken.balanceOf(address(fl)), 0);
        assertEq(loanToken.balanceOf(address(fl)), 0);
    }

    function test_increaseLeverage_nonCorrelated() external {
        uint256 posId = _openNonCorrelatedPosition(
            alice,
            INITIAL_COLLATERAL,
            40e16
        );

        LeveragePosition memory posBefore = fl.getUserLeveragePosition(
            alice,
            posId
        );
        Position memory morphoBefore = fl.getMorphoPosition(
            posBefore.userProxy,
            nonCorrelatedMarket
        );

        uint256 flashLoan = 500e6; // 500 USDC
        uint256 swapOut = _calcSwapOutput(flashLoan, nonCorrelatedMarket);
        SwapData memory swap = _buildSwapData(
            address(ncLoanToken),
            address(ncCollateralToken),
            flashLoan,
            swapOut
        );

        vm.prank(alice);
        fl.increaseLeverage(posId, flashLoan, swap, 0);

        Position memory morphoAfter = fl.getMorphoPosition(
            posBefore.userProxy,
            nonCorrelatedMarket
        );
        assertGt(morphoAfter.collateral, morphoBefore.collateral);
        assertGt(morphoAfter.borrowShares, morphoBefore.borrowShares);
    }

    function test_increaseLeverage_multipleTimesOnSamePosition() external {
        uint256 posId = _openCorrelatedPosition(
            alice,
            INITIAL_COLLATERAL,
            40e16
        );
        uint256 increaseCount = 3;

        LeveragePosition memory posStart = fl.getUserLeveragePosition(
            alice,
            posId
        );
        Position memory morphoStart = fl.getMorphoPosition(
            posStart.userProxy,
            correlatedMarket
        );

        for (uint256 i; i < increaseCount; i++) {
            _increaseLeverageAsAlice(posId, 1e18, correlatedMarket);
        }

        Position memory morphoEnd = fl.getMorphoPosition(
            posStart.userProxy,
            correlatedMarket
        );
        assertGt(
            morphoEnd.collateral,
            morphoStart.collateral,
            "Collateral should grow"
        );
        assertGt(
            morphoEnd.borrowShares,
            morphoStart.borrowShares,
            "Debt should grow"
        );

        LeveragePosition memory posEnd = fl.getUserLeveragePosition(
            alice,
            posId
        );
        assertEq(
            posEnd.amountDepositedInLoanToken,
            posStart.amountDepositedInLoanToken,
            "Deposited unchanged"
        );
    }

    function test_increaseLeverage_rightAfterOpening() external {
        uint256 posId = _openCorrelatedPosition(
            alice,
            INITIAL_COLLATERAL,
            40e16
        );
        _increaseLeverageAsAlice(posId, 2e18, correlatedMarket);

        LeveragePosition memory pos = fl.getUserLeveragePosition(alice, posId);
        Position memory morphoPos = fl.getMorphoPosition(
            pos.userProxy,
            correlatedMarket
        );

        assertGt(
            morphoPos.collateral,
            INITIAL_COLLATERAL,
            "Collateral should exceed initial"
        );
        assertTrue(pos.open);
    }

    // ─── Revert cases ───

    function test_increaseLeverage_revertsOnClosedPosition() external {
        uint256 posId = _openCorrelatedPosition(
            alice,
            INITIAL_COLLATERAL,
            STANDARD_LTV
        );
        _deleveragePosition(alice, posId, correlatedMarket);

        vm.prank(alice);
        vm.expectRevert(FLError.FlashLeverage__PositionAlreadyClosed.selector);
        fl.increaseLeverage(posId, 1e18, _emptySwap(), 0);
    }

    function test_increaseLeverage_revertsOnZeroAmount() external {
        uint256 posId = _openCorrelatedPosition(
            alice,
            INITIAL_COLLATERAL,
            STANDARD_LTV
        );

        vm.prank(alice);
        vm.expectRevert(FLError.FlashLeverage__AmountCannotBeZero.selector);
        fl.increaseLeverage(posId, 0, _emptySwap(), 0);
    }

    function test_increaseLeverage_revertsOnExceedingLTV() external {
        uint256 posId = _openCorrelatedPosition(
            alice,
            INITIAL_COLLATERAL,
            85e16
        );

        uint256 excessiveFlashLoan = 200e18;
        uint256 swapOut = _calcSwapOutput(excessiveFlashLoan, correlatedMarket);
        SwapData memory swap = _buildSwapData(
            address(loanToken),
            address(collateralToken),
            excessiveFlashLoan,
            swapOut
        );

        vm.prank(alice);
        vm.expectRevert();
        fl.increaseLeverage(posId, excessiveFlashLoan, swap, 0);
    }

    function test_increaseLeverage_revertsOnNonOwner() external {
        uint256 posId = _openCorrelatedPosition(
            alice,
            INITIAL_COLLATERAL,
            50e16
        );

        vm.prank(bob);
        vm.expectRevert();
        fl.increaseLeverage(posId, 1e18, _emptySwap(), 0);
    }

    // ─── Internal helpers ───

    function _increaseLeverageAsAlice(
        uint256 posId,
        uint256 flashLoanAmount,
        MarketParams memory mkt
    ) internal {
        uint256 swapOut = _calcSwapOutput(flashLoanAmount, mkt);
        SwapData memory swap = _buildSwapData(
            mkt.loanToken,
            mkt.collateralToken,
            flashLoanAmount,
            swapOut
        );

        vm.prank(alice);
        fl.increaseLeverage(posId, flashLoanAmount, swap, 0);
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
        fl.deleverage(posId, 0, swap, 0);
    }

    function _emptySwap() internal view returns (SwapData memory) {
        return SwapData({extRouter: address(router), extCalldata: ""});
    }
}
