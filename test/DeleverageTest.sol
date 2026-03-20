// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import "./TestBase.sol";
import {FLError} from "src/core/libraries/Error.sol";

/// @title DeleverageTest
/// @notice Tests for closing leveraged positions via FlashLeverage::deleverage
contract DeleverageTest is TestBase {
    using Math for uint256;

    uint256 constant INITIAL_COLLATERAL = 10e18;
    uint256 constant STANDARD_LTV = 70e16; // 70%

    // ─── Happy path ───

    function test_deleverage_correlated_fullVerification() external {
        uint256 posId = _openCorrelatedPosition(
            alice,
            INITIAL_COLLATERAL,
            STANDARD_LTV
        );

        LeveragePosition memory posBefore = fl.getUserLeveragePosition(
            alice,
            posId
        );
        uint256 depositedBefore = posBefore.amountDepositedInLoanToken;
        uint256 aliceBefore = loanToken.balanceOf(alice);

        _deleveragePosition(alice, posId, correlatedMarket);

        LeveragePosition memory posAfter = fl.getUserLeveragePosition(
            alice,
            posId
        );
        Position memory morphoAfter = fl.getMorphoPosition(
            posAfter.userProxy,
            correlatedMarket
        );

        // Position closed
        assertFalse(posAfter.open);

        // Morpho fully cleared
        assertEq(morphoAfter.collateral, 0, "Morpho collateral should be 0");
        assertEq(morphoAfter.borrowShares, 0, "Morpho debt should be 0");

        // amountReturnedInLoanToken set
        assertGt(
            posAfter.amountReturnedInLoanToken,
            0,
            "Should record returned amount"
        );

        // User received tokens
        uint256 aliceReceived = loanToken.balanceOf(alice) - aliceBefore;
        assertEq(
            aliceReceived,
            posAfter.amountReturnedInLoanToken,
            "Alice should receive recorded return amount"
        );

        // amountDepositedInLoanToken unchanged
        assertEq(
            posAfter.amountDepositedInLoanToken,
            depositedBefore,
            "Deposited should not change on deleverage"
        );

        // No tokens left in contract
        assertEq(collateralToken.balanceOf(address(fl)), 0);
        assertEq(loanToken.balanceOf(address(fl)), 0);
    }

    function test_deleverage_nonCorrelated_fullVerification() external {
        uint256 posId = _openNonCorrelatedPosition(
            alice,
            INITIAL_COLLATERAL,
            50e16
        );

        uint256 aliceBefore = ncLoanToken.balanceOf(alice);

        _deleveragePosition(alice, posId, nonCorrelatedMarket);

        LeveragePosition memory posAfter = fl.getUserLeveragePosition(
            alice,
            posId
        );
        Position memory morphoAfter = fl.getMorphoPosition(
            posAfter.userProxy,
            nonCorrelatedMarket
        );

        assertFalse(posAfter.open);
        assertEq(morphoAfter.collateral, 0);
        assertEq(morphoAfter.borrowShares, 0);
        assertGt(posAfter.amountReturnedInLoanToken, 0);
        assertEq(
            ncLoanToken.balanceOf(alice) - aliceBefore,
            posAfter.amountReturnedInLoanToken
        );
    }

    // ─── Yield fee verification ───

    function test_deleverage_correlated_yieldFeeAccuracy() external {
        uint256 posId = _openCorrelatedPosition(
            alice,
            INITIAL_COLLATERAL,
            STANDARD_LTV
        );

        LeveragePosition memory posBefore = fl.getUserLeveragePosition(
            alice,
            posId
        );
        uint256 deposited = posBefore.amountDepositedInLoanToken;

        // 10% appreciation
        correlatedOracle.setPrice((CORRELATED_PRICE * 110) / 100);

        uint256 treasuryBefore = loanToken.balanceOf(treasury);
        uint256 aliceBefore = loanToken.balanceOf(alice);

        _deleveragePosition(alice, posId, correlatedMarket);

        uint256 fee = loanToken.balanceOf(treasury) - treasuryBefore;
        uint256 aliceReceived = loanToken.balanceOf(alice) - aliceBefore;

        LeveragePosition memory posAfter = fl.getUserLeveragePosition(
            alice,
            posId
        );
        uint256 totalReturned = aliceReceived + fee;

        // Fee should be 10% of yield (totalReturned - deposited)
        assertGt(fee, 0, "Should charge yield fee");
        assertGt(totalReturned, deposited, "Position should be profitable");

        uint256 yield = totalReturned - deposited;
        uint256 expectedFee = yield.mulDown(fl.s_yieldFee());
        assertApproxEqAbs(
            fee,
            expectedFee,
            1,
            "Fee should be yieldFee% of yield"
        );

        // Alice receives total minus fee
        assertEq(
            posAfter.amountReturnedInLoanToken,
            aliceReceived,
            "Recorded return matches alice received"
        );
    }

    function test_deleverage_correlated_noYield_noFee() external {
        uint256 posId = _openCorrelatedPosition(
            alice,
            INITIAL_COLLATERAL,
            STANDARD_LTV
        );

        // No price change = no yield
        uint256 treasuryBefore = loanToken.balanceOf(treasury);

        _deleveragePosition(alice, posId, correlatedMarket);

        assertEq(
            loanToken.balanceOf(treasury),
            treasuryBefore,
            "No yield = no fee"
        );
    }

    function test_deleverage_nonCorrelated_noYieldFee_evenWithAppreciation()
        external
    {
        uint256 posId = _openNonCorrelatedPosition(
            alice,
            INITIAL_COLLATERAL,
            50e16
        );

        // 50% appreciation — non-correlated should still have no yield fee
        nonCorrelatedOracle.setPrice((NON_CORRELATED_PRICE * 150) / 100);

        uint256 treasuryBefore = ncLoanToken.balanceOf(treasury);

        _deleveragePosition(alice, posId, nonCorrelatedMarket);

        assertEq(
            ncLoanToken.balanceOf(treasury),
            treasuryBefore,
            "No yield fee on non-correlated"
        );
    }

    // ─── Loss scenarios ───

    // ─── Loss scenarios (slippage) ───

    function test_deleverage_correlated_swapSlippage_noFee() external {
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

        // Swap returns 5% less than oracle price — simulates slippage
        uint256 colVal = fl.getCollateralValueInLoanToken(
            correlatedMarket,
            morphoPos.collateral
        );
        uint256 slippedOutput = (colVal * 95) / 100;
        SwapData memory swap = _buildSwapData(
            address(collateralToken),
            address(loanToken),
            morphoPos.collateral,
            slippedOutput
        );

        uint256 treasuryBefore = loanToken.balanceOf(treasury);
        uint256 aliceBefore = loanToken.balanceOf(alice);

        vm.prank(alice);
        fl.deleverage(posId, swap, 0);

        LeveragePosition memory posAfter = fl.getUserLeveragePosition(
            alice,
            posId
        );

        assertFalse(posAfter.open);
        assertEq(
            loanToken.balanceOf(treasury),
            treasuryBefore,
            "No fee when slippage eats profit"
        );

        // User still gets something back
        uint256 aliceReceived = loanToken.balanceOf(alice) - aliceBefore;
        assertGt(aliceReceived, 0, "Should still receive some tokens");
    }

    function test_deleverage_correlated_heavySlippage_returnsZero() external {
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

        // Swap returns just barely enough to cover flash loan — user gets nothing
        uint256 debt = fl.getSharesValueInLoanToken(
            correlatedMarket,
            morphoPos.borrowShares
        );
        SwapData memory swap = _buildSwapData(
            address(collateralToken),
            address(loanToken),
            morphoPos.collateral,
            debt
        );

        uint256 aliceBefore = loanToken.balanceOf(alice);

        vm.prank(alice);
        fl.deleverage(posId, swap, 0);

        LeveragePosition memory posAfter = fl.getUserLeveragePosition(
            alice,
            posId
        );

        assertFalse(posAfter.open);
        assertEq(
            posAfter.amountReturnedInLoanToken,
            0,
            "Should return 0 when swap only covers debt"
        );
        assertEq(
            loanToken.balanceOf(alice),
            aliceBefore,
            "Alice receives nothing"
        );
    }

    // ─── Zero debt path ───

    function test_deleverage_afterFullRepay() external {
        uint256 posId = _openCorrelatedPosition(
            alice,
            INITIAL_COLLATERAL,
            STANDARD_LTV
        );

        // Fully repay debt
        _repayAllDebt(alice, posId, correlatedMarket);

        LeveragePosition memory pos = fl.getUserLeveragePosition(alice, posId);
        Position memory morphoPos = fl.getMorphoPosition(
            pos.userProxy,
            correlatedMarket
        );
        assertEq(
            morphoPos.borrowShares,
            0,
            "Debt should be zero before deleverage"
        );

        uint256 aliceBefore = loanToken.balanceOf(alice);

        _deleveragePosition(alice, posId, correlatedMarket);

        LeveragePosition memory posAfter = fl.getUserLeveragePosition(
            alice,
            posId
        );
        assertFalse(posAfter.open);
        assertGt(
            loanToken.balanceOf(alice),
            aliceBefore,
            "Should receive collateral value"
        );
    }

    // ─── Revert cases ───

    function test_deleverage_revertsOnAlreadyClosed() external {
        uint256 posId = _openCorrelatedPosition(
            alice,
            INITIAL_COLLATERAL,
            STANDARD_LTV
        );
        _deleveragePosition(alice, posId, correlatedMarket);

        vm.prank(alice);
        vm.expectRevert(FLError.FlashLeverage__PositionAlreadyClosed.selector);
        fl.deleverage(posId, _emptySwap(), 0);
    }

    function test_deleverage_revertsOnNonOwner() external {
        uint256 posId = _openCorrelatedPosition(
            alice,
            INITIAL_COLLATERAL,
            STANDARD_LTV
        );

        vm.prank(bob);
        vm.expectRevert();
        fl.deleverage(posId, _emptySwap(), 0);
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

    function _repayAllDebt(
        address user,
        uint256 posId,
        MarketParams memory mkt
    ) internal {
        LeveragePosition memory pos = fl.getUserLeveragePosition(user, posId);
        Position memory morphoPos = fl.getMorphoPosition(pos.userProxy, mkt);
        uint256 debt = fl.getSharesValueInLoanToken(
            mkt,
            morphoPos.borrowShares
        );

        MockERC20(mkt.loanToken).mint(user, debt);

        vm.startPrank(user);
        MockERC20(mkt.loanToken).approve(address(fl), debt);
        fl.repay(user, posId, debt, morphoPos.borrowShares);
        vm.stopPrank();
    }

    function _emptySwap() internal view returns (SwapData memory) {
        return SwapData({extRouter: address(router), extCalldata: ""});
    }
}
