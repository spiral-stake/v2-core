// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import "./TestBase.sol";
import {FLError} from "src/core/libraries/Error.sol";

/// @title SupplyCollateralTest
/// @notice Tests for FlashLeverage::supplyCollateral
contract SupplyCollateralTest is TestBase {
    using Math for uint256;

    uint256 constant INITIAL_COLLATERAL = 10e18;
    uint256 constant STANDARD_LTV = 70e16; // 70%
    uint256 constant SUPPLY_AMOUNT = 5e18;

    // ─── Happy path ───

    function test_supplyCollateral_correlated_fullVerification() external {
        uint256 posId = _openCorrelatedPosition(
            alice,
            INITIAL_COLLATERAL,
            STANDARD_LTV
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

        collateralToken.mint(alice, SUPPLY_AMOUNT);
        uint256 aliceAfterMint = collateralToken.balanceOf(alice);

        vm.startPrank(alice);
        collateralToken.approve(address(fl), SUPPLY_AMOUNT);
        fl.supplyCollateral(alice, posId, SUPPLY_AMOUNT);
        vm.stopPrank();

        LeveragePosition memory posAfter = fl.getUserLeveragePosition(
            alice,
            posId
        );
        Position memory morphoAfter = fl.getMorphoPosition(
            posAfter.userProxy,
            correlatedMarket
        );

        // Deposited delta accuracy
        uint256 expectedDepositedDelta = fl.getCollateralValueInLoanToken(
            correlatedMarket,
            SUPPLY_AMOUNT
        );
        assertEq(
            posAfter.amountDepositedInLoanToken,
            depositedBefore + expectedDepositedDelta,
            "Deposited should increase by exact collateral value in loan token"
        );

        // Morpho collateral delta accuracy
        assertEq(
            morphoAfter.collateral,
            morphoBefore.collateral + SUPPLY_AMOUNT,
            "Morpho collateral should increase by exact supply amount"
        );

        // Debt unchanged
        assertEq(
            morphoAfter.borrowShares,
            morphoBefore.borrowShares,
            "Debt should not change"
        );

        // Exact tokens pulled
        assertEq(
            collateralToken.balanceOf(alice),
            aliceAfterMint - SUPPLY_AMOUNT,
            "Exact supply pulled from alice"
        );

        // No tokens left in contract
        assertEq(collateralToken.balanceOf(address(fl)), 0);
        assertEq(loanToken.balanceOf(address(fl)), 0);
    }

    function test_supplyCollateral_nonCorrelated_fullVerification() external {
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

        ncCollateralToken.mint(alice, SUPPLY_AMOUNT);

        vm.startPrank(alice);
        ncCollateralToken.approve(address(fl), SUPPLY_AMOUNT);
        fl.supplyCollateral(alice, posId, SUPPLY_AMOUNT);
        vm.stopPrank();

        Position memory morphoAfter = fl.getMorphoPosition(
            posBefore.userProxy,
            nonCorrelatedMarket
        );

        // Morpho receives collateral minus fee
        uint256 feeAmount = SUPPLY_AMOUNT.mulDown(fl.s_depositFee());
        uint256 collateralAfterFee = SUPPLY_AMOUNT - feeAmount;
        assertEq(
            morphoAfter.collateral,
            morphoBefore.collateral + collateralAfterFee,
            "Morpho should receive supply minus deposit fee"
        );

        // Debt unchanged
        assertEq(
            morphoAfter.borrowShares,
            morphoBefore.borrowShares,
            "Debt should not change"
        );
    }

    // ─── Fee verification ───

    function test_supplyCollateral_nonCorrelated_exactDepositFee() external {
        uint256 posId = _openNonCorrelatedPosition(
            alice,
            INITIAL_COLLATERAL,
            50e16
        );

        ncCollateralToken.mint(alice, SUPPLY_AMOUNT);
        uint256 treasuryBefore = ncCollateralToken.balanceOf(treasury);

        vm.startPrank(alice);
        ncCollateralToken.approve(address(fl), SUPPLY_AMOUNT);
        fl.supplyCollateral(alice, posId, SUPPLY_AMOUNT);
        vm.stopPrank();

        uint256 fee = ncCollateralToken.balanceOf(treasury) - treasuryBefore;
        assertEq(
            fee,
            SUPPLY_AMOUNT.mulDown(fl.s_depositFee()),
            "Fee should be exact depositFee percentage"
        );
    }

    function test_supplyCollateral_correlated_noDepositFee() external {
        uint256 posId = _openCorrelatedPosition(
            alice,
            INITIAL_COLLATERAL,
            STANDARD_LTV
        );

        collateralToken.mint(alice, SUPPLY_AMOUNT);
        uint256 treasuryBefore = collateralToken.balanceOf(treasury);

        vm.startPrank(alice);
        collateralToken.approve(address(fl), SUPPLY_AMOUNT);
        fl.supplyCollateral(alice, posId, SUPPLY_AMOUNT);
        vm.stopPrank();

        assertEq(
            collateralToken.balanceOf(treasury),
            treasuryBefore,
            "No fee for correlated"
        );
    }

    // ─── Accumulation ───

    function test_supplyCollateral_multipleSuppliesAccumulate() external {
        uint256 posId = _openCorrelatedPosition(
            alice,
            INITIAL_COLLATERAL,
            STANDARD_LTV
        );
        uint256 supplyCount = 3;

        LeveragePosition memory posStart = fl.getUserLeveragePosition(
            alice,
            posId
        );
        Position memory morphoStart = fl.getMorphoPosition(
            posStart.userProxy,
            correlatedMarket
        );
        uint256 depositedStart = posStart.amountDepositedInLoanToken;

        uint256 perSupplyValue = fl.getCollateralValueInLoanToken(
            correlatedMarket,
            SUPPLY_AMOUNT
        );

        for (uint256 i; i < supplyCount; i++) {
            _supplyAsAlice(posId, SUPPLY_AMOUNT, correlatedMarket);
        }

        LeveragePosition memory posEnd = fl.getUserLeveragePosition(
            alice,
            posId
        );
        Position memory morphoEnd = fl.getMorphoPosition(
            posEnd.userProxy,
            correlatedMarket
        );

        assertEq(
            posEnd.amountDepositedInLoanToken,
            depositedStart + (perSupplyValue * supplyCount),
            "Deposited should accumulate across supplies"
        );
        assertEq(
            morphoEnd.collateral,
            morphoStart.collateral + (SUPPLY_AMOUNT * supplyCount),
            "Morpho collateral should accumulate"
        );
    }

    // ─── LTV ───

    function test_supplyCollateral_reducesEffectiveLTV() external {
        uint256 posId = _openCorrelatedPosition(
            alice,
            INITIAL_COLLATERAL,
            80e16
        );

        LeveragePosition memory pos = fl.getUserLeveragePosition(alice, posId);
        Position memory morphoBefore = fl.getMorphoPosition(
            pos.userProxy,
            correlatedMarket
        );

        _supplyAsAlice(posId, 20e18, correlatedMarket);

        Position memory morphoAfter = fl.getMorphoPosition(
            pos.userProxy,
            correlatedMarket
        );
        assertGt(
            morphoAfter.collateral,
            morphoBefore.collateral,
            "Collateral should increase"
        );
        assertEq(
            morphoAfter.borrowShares,
            morphoBefore.borrowShares,
            "Debt should not change"
        );
    }

    // ─── Revert cases ───

    function test_supplyCollateral_revertsOnClosedPosition() external {
        uint256 posId = _openCorrelatedPosition(
            alice,
            INITIAL_COLLATERAL,
            STANDARD_LTV
        );
        _deleveragePosition(alice, posId, correlatedMarket);

        collateralToken.mint(alice, SUPPLY_AMOUNT);
        vm.startPrank(alice);
        collateralToken.approve(address(fl), SUPPLY_AMOUNT);
        vm.expectRevert(FLError.FlashLeverage__PositionAlreadyClosed.selector);
        fl.supplyCollateral(alice, posId, SUPPLY_AMOUNT);
        vm.stopPrank();
    }

    function test_supplyCollateral_revertsOnZeroAmount() external {
        uint256 posId = _openCorrelatedPosition(
            alice,
            INITIAL_COLLATERAL,
            STANDARD_LTV
        );

        vm.expectRevert(FLError.FlashLeverage__AmountCannotBeZero.selector);
        fl.supplyCollateral(alice, posId, 0);
    }

    // ─── Internal helpers ───

    function _supplyAsAlice(
        uint256 posId,
        uint256 amount,
        MarketParams memory mkt
    ) internal {
        MockERC20(mkt.collateralToken).mint(alice, amount);

        vm.startPrank(alice);
        MockERC20(mkt.collateralToken).approve(address(fl), amount);
        fl.supplyCollateral(alice, posId, amount);
        vm.stopPrank();
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
        fl.deleverage(posId, swap, 0);
    }
}
