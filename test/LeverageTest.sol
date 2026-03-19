// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import "./TestBase.sol";
import {FLError} from "src/core/libraries/Error.sol";

/// @title LeverageTest
/// @notice Tests for opening leveraged positions via FlashLeverage::leverage
contract LeverageTest is TestBase {
    // ─── Happy path ───

    function test_leverage_correlated_opensPosition() external {
        uint256 collateral = 10e18;
        uint256 posId = _openCorrelatedPosition(alice, collateral, 70e16);

        LeveragePosition memory pos = fl.getUserLeveragePosition(alice, posId);
        assertTrue(pos.open, "Position should be open");
        assertTrue(pos.userProxy != address(0), "UserProxy should be created");
        assertGt(
            pos.amountDepositedInLoanToken,
            0,
            "Deposited amount should be tracked"
        );
        assertEq(pos.marketId, correlatedMarketId, "Market ID should match");
    }

    function test_leverage_nonCorrelated_opensPosition() external {
        uint256 collateral = 10e18;
        uint256 posId = _openNonCorrelatedPosition(alice, collateral, 50e16);

        LeveragePosition memory pos = fl.getUserLeveragePosition(alice, posId);
        assertTrue(pos.open, "Position should be open");
        assertTrue(pos.userProxy != address(0), "UserProxy should be created");
    }

    function test_leverage_nonCorrelated_chargesDepositFee() external {
        uint256 collateral = 100e18;
        uint256 treasuryBefore = ncCollateralToken.balanceOf(treasury);

        _openNonCorrelatedPosition(alice, collateral, 50e16);

        uint256 treasuryAfter = ncCollateralToken.balanceOf(treasury);
        assertGt(
            treasuryAfter,
            treasuryBefore,
            "Treasury should receive deposit fee"
        );
    }

    function test_leverage_correlated_noDepositFee() external {
        uint256 collateral = 10e18;
        uint256 treasuryBefore = collateralToken.balanceOf(treasury);

        _openCorrelatedPosition(alice, collateral, 70e16);

        uint256 treasuryAfter = collateralToken.balanceOf(treasury);
        assertEq(
            treasuryAfter,
            treasuryBefore,
            "No deposit fee for correlated markets"
        );
    }

    function test_leverage_multiplePositions() external {
        _openCorrelatedPosition(alice, 10e18, 70e16);
        _openCorrelatedPosition(alice, 5e18, 60e16);

        LeveragePosition[] memory positions = fl.getUserLeveragePositions(
            alice
        );
        assertEq(positions.length, 2, "Should have 2 positions");
        assertTrue(
            positions[0].open && positions[1].open,
            "Both should be open"
        );
    }

    function test_leverage_differentUsers() external {
        _openCorrelatedPosition(alice, 10e18, 70e16);
        _openCorrelatedPosition(bob, 15e18, 60e16);

        assertEq(fl.getUserLeveragePositions(alice).length, 1);
        assertEq(fl.getUserLeveragePositions(bob).length, 1);
    }

    // ─── Revert cases ───

    function test_leverage_revertsOnUnsupportedMarket() external {
        bytes32 fakeMarketId = keccak256("fake");

        collateralToken.mint(alice, 10e18);
        vm.startPrank(alice);
        collateralToken.approve(address(fl), 10e18);

        vm.expectRevert(FLError.FlashLeverage__UnsupportedMarket.selector);
        fl.leverage(
            alice,
            LeverageParams({
                marketId: fakeMarketId,
                amountCollateral: 10e18,
                amountFlashLoan: 5e18,
                swapData: SwapData({
                    extRouter: address(router),
                    extCalldata: ""
                }),
                minTokenOut: 0
            })
        );
        vm.stopPrank();
    }

    function test_leverage_revertsOnZeroCollateral() external {
        vm.prank(alice);
        vm.expectRevert(FLError.FlashLeverage__AmountCannotBeZero.selector);
        fl.leverage(
            alice,
            LeverageParams({
                marketId: correlatedMarketId,
                amountCollateral: 0,
                amountFlashLoan: 5e18,
                swapData: SwapData({
                    extRouter: address(router),
                    extCalldata: ""
                }),
                minTokenOut: 0
            })
        );
    }

    function test_leverage_revertsOnZeroFlashLoan() external {
        vm.prank(alice);
        vm.expectRevert(FLError.FlashLeverage__AmountCannotBeZero.selector);
        fl.leverage(
            alice,
            LeverageParams({
                marketId: correlatedMarketId,
                amountCollateral: 10e18,
                amountFlashLoan: 0,
                swapData: SwapData({
                    extRouter: address(router),
                    extCalldata: ""
                }),
                minTokenOut: 0
            })
        );
    }

    function test_leverage_revertsOnDisabledMarket() external {
        fl.setMarketEnabled(correlatedMarketId, false);

        collateralToken.mint(alice, 10e18);
        vm.startPrank(alice);
        collateralToken.approve(address(fl), 10e18);

        vm.expectRevert(FLError.FlashLeverage__UnsupportedMarket.selector);
        fl.leverage(
            alice,
            LeverageParams({
                marketId: correlatedMarketId,
                amountCollateral: 10e18,
                amountFlashLoan: 5e18,
                swapData: SwapData({
                    extRouter: address(router),
                    extCalldata: ""
                }),
                minTokenOut: 0
            })
        );
        vm.stopPrank();
    }

    // ─── Operator whitelist ───

    function test_leverage_revertsOnUnauthorizedCaller() external {
        collateralToken.mint(bob, 10e18);

        vm.startPrank(bob);
        collateralToken.approve(address(fl), 10e18);

        vm.expectRevert(FLError.FlashLeverage__NotApprovedOperator.selector);
        fl.leverage(
            alice, // bob tries to open for alice
            LeverageParams({
                marketId: correlatedMarketId,
                amountCollateral: 10e18,
                amountFlashLoan: 5e18,
                swapData: SwapData({
                    extRouter: address(router),
                    extCalldata: ""
                }),
                minTokenOut: 0
            })
        );
        vm.stopPrank();
    }

    function test_leverage_approvedOperatorCanOpen() external {
        fl.setApprovedOperator(bob, true);

        collateralToken.mint(bob, 10e18);
        uint256 flashLoan = _calcFlashLoan(70e16, 10e18, correlatedMarket);
        uint256 swapOut = _calcSwapOutput(flashLoan, correlatedMarket);
        SwapData memory swap = _buildSwapData(
            address(loanToken),
            address(collateralToken),
            flashLoan,
            swapOut
        );

        vm.startPrank(bob);
        collateralToken.approve(address(fl), 10e18);
        fl.leverage(
            alice, // bob opens on behalf of alice
            LeverageParams({
                marketId: correlatedMarketId,
                amountCollateral: 10e18,
                amountFlashLoan: flashLoan,
                swapData: swap,
                minTokenOut: 0
            })
        );
        vm.stopPrank();

        assertEq(
            fl.getUserLeveragePositions(alice).length,
            1,
            "Alice should have a position"
        );
    }

    // ─── LTV check ───

    function test_leverage_revertsOnExceedingMaxLTV() external {
        uint256 collateral = 1e18;
        // Try to borrow way too much
        uint256 flashLoan = 100e18;
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
}
