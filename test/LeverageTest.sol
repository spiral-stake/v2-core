// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import "./TestBase.sol";
import {FLError} from "src/core/libraries/Error.sol";

/// @title LeverageTest
/// @notice Tests for opening leveraged positions via FlashLeverage::leverage
contract LeverageTest is TestBase {
    using Math for uint256;

    uint256 constant INITIAL_COLLATERAL = 10e18;
    uint256 constant STANDARD_LTV = 70e16; // 70%

    // ─── Happy path ───

    function test_leverage_correlated_fullVerification() external {
        uint256 flashLoan = _calcFlashLoan(
            STANDARD_LTV,
            INITIAL_COLLATERAL,
            correlatedMarket
        );
        uint256 swapOut = _calcSwapOutput(flashLoan, correlatedMarket);

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

        // Position struct
        assertTrue(pos.open);
        assertEq(pos.marketId, correlatedMarketId);
        assertTrue(pos.userProxy != address(0));
        assertEq(pos.amountReturnedInLoanToken, 0);
        assertEq(
            pos.amountDepositedInLoanToken,
            fl.getCollateralValueInLoanToken(
                correlatedMarket,
                INITIAL_COLLATERAL
            )
        );

        // Morpho state
        assertEq(morphoPos.collateral, INITIAL_COLLATERAL + swapOut);
        assertApproxEqAbs(
            fl.getSharesValueInLoanToken(
                correlatedMarket,
                morphoPos.borrowShares
            ),
            flashLoan,
            1
        );

        // No tokens left in contract
        assertEq(collateralToken.balanceOf(address(fl)), 0);
        assertEq(loanToken.balanceOf(address(fl)), 0);
    }

    function test_leverage_nonCorrelated_fullVerification() external {
        uint256 posId = _openNonCorrelatedPosition(
            alice,
            INITIAL_COLLATERAL,
            50e16
        );

        LeveragePosition memory pos = fl.getUserLeveragePosition(alice, posId);
        assertTrue(pos.open);
        assertEq(pos.marketId, nonCorrelatedMarketId);
        assertTrue(pos.userProxy != address(0));
        assertGt(pos.amountDepositedInLoanToken, 0);
        assertEq(pos.amountReturnedInLoanToken, 0);
    }

    // ─── Slippage verification ───

    function test_leverage_swapSlippage_reducesCollateral() external {
        uint256 flashLoan = _calcFlashLoan(
            STANDARD_LTV,
            INITIAL_COLLATERAL,
            correlatedMarket
        );
        uint256 fairSwapOut = _calcSwapOutput(flashLoan, correlatedMarket);

        // 2% slippage — swap returns less collateral than oracle price suggests
        uint256 slippedSwapOut = (fairSwapOut * 98) / 100;
        SwapData memory swap = _buildSwapData(
            address(loanToken),
            address(collateralToken),
            flashLoan,
            slippedSwapOut
        );

        collateralToken.mint(alice, INITIAL_COLLATERAL);
        vm.startPrank(alice);
        collateralToken.approve(address(fl), INITIAL_COLLATERAL);
        fl.leverage(
            alice,
            LeverageParams({
                marketId: correlatedMarketId,
                amountCollateral: INITIAL_COLLATERAL,
                amountFlashLoan: flashLoan,
                swapData: swap,
                minTokenOut: 0
            })
        );
        vm.stopPrank();

        LeveragePosition memory pos = fl.getUserLeveragePosition(alice, 0);
        Position memory morphoPos = fl.getMorphoPosition(
            pos.userProxy,
            correlatedMarket
        );

        // Collateral = user deposit + slipped swap output (not fair output)
        assertEq(morphoPos.collateral, INITIAL_COLLATERAL + slippedSwapOut);
        assertLt(
            morphoPos.collateral,
            INITIAL_COLLATERAL + fairSwapOut,
            "Slippage should reduce total collateral"
        );
    }

    function test_leverage_minTokenOut_protectsAgainstSlippage() external {
        uint256 flashLoan = _calcFlashLoan(
            STANDARD_LTV,
            INITIAL_COLLATERAL,
            correlatedMarket
        );
        uint256 fairSwapOut = _calcSwapOutput(flashLoan, correlatedMarket);

        // 5% slippage
        uint256 slippedSwapOut = (fairSwapOut * 95) / 100;
        SwapData memory swap = _buildSwapData(
            address(loanToken),
            address(collateralToken),
            flashLoan,
            slippedSwapOut
        );

        // minTokenOut set to fair output — should revert because swap returns less
        collateralToken.mint(alice, INITIAL_COLLATERAL);
        vm.startPrank(alice);
        collateralToken.approve(address(fl), INITIAL_COLLATERAL);
        vm.expectRevert(FLError.FlashLeverage__MinTokenOutNotMet.selector);
        fl.leverage(
            alice,
            LeverageParams({
                marketId: correlatedMarketId,
                amountCollateral: INITIAL_COLLATERAL,
                amountFlashLoan: flashLoan,
                swapData: swap,
                minTokenOut: fairSwapOut
            })
        );
        vm.stopPrank();
    }

    function test_leverage_multiplePositions_uniqueProxies() external {
        _openCorrelatedPosition(alice, INITIAL_COLLATERAL, STANDARD_LTV);
        _openCorrelatedPosition(alice, 5e18, 60e16);

        LeveragePosition[] memory positions = fl.getUserLeveragePositions(
            alice
        );
        assertEq(positions.length, 2);
        assertTrue(positions[0].open && positions[1].open);
        assertTrue(positions[0].userProxy != positions[1].userProxy);
    }

    function test_leverage_differentUsers_isolated() external {
        _openCorrelatedPosition(alice, INITIAL_COLLATERAL, STANDARD_LTV);
        _openCorrelatedPosition(bob, 15e18, 60e16);

        assertEq(fl.getUserLeveragePositions(alice).length, 1);
        assertEq(fl.getUserLeveragePositions(bob).length, 1);
    }

    // ─── Fee verification ───

    function test_leverage_nonCorrelated_exactDepositFee() external {
        uint256 largeCollateral = 100e18;
        uint256 treasuryBefore = ncCollateralToken.balanceOf(treasury);

        _openNonCorrelatedPosition(alice, largeCollateral, 50e16);

        uint256 fee = ncCollateralToken.balanceOf(treasury) - treasuryBefore;
        assertEq(fee, largeCollateral.mulDown(fl.s_depositFee()));
    }

    function test_leverage_correlated_noDepositFee() external {
        uint256 treasuryBefore = collateralToken.balanceOf(treasury);
        _openCorrelatedPosition(alice, INITIAL_COLLATERAL, STANDARD_LTV);
        assertEq(collateralToken.balanceOf(treasury), treasuryBefore);
    }

    // ─── Token flow verification ───

    function test_leverage_onlyExactCollateralPulled() external {
        uint256 extraBalance = 50e18;
        collateralToken.mint(alice, INITIAL_COLLATERAL + extraBalance);

        uint256 aliceBefore = collateralToken.balanceOf(alice);
        _leverageAsAlice(
            INITIAL_COLLATERAL,
            STANDARD_LTV,
            correlatedMarket,
            correlatedMarketId
        );

        assertEq(
            collateralToken.balanceOf(alice),
            aliceBefore - INITIAL_COLLATERAL
        );
    }

    function test_leverage_operatorPaysTokensNotUser() external {
        fl.setApprovedOperator(bob, true);
        collateralToken.mint(bob, INITIAL_COLLATERAL);

        uint256 aliceBefore = collateralToken.balanceOf(alice);
        uint256 bobBefore = collateralToken.balanceOf(bob);

        uint256 flashLoan = _calcFlashLoan(
            STANDARD_LTV,
            INITIAL_COLLATERAL,
            correlatedMarket
        );
        uint256 swapOut = _calcSwapOutput(flashLoan, correlatedMarket);
        SwapData memory swap = _buildSwapData(
            address(loanToken),
            address(collateralToken),
            flashLoan,
            swapOut
        );

        vm.startPrank(bob);
        collateralToken.approve(address(fl), INITIAL_COLLATERAL);
        fl.leverage(
            alice,
            LeverageParams({
                marketId: correlatedMarketId,
                amountCollateral: INITIAL_COLLATERAL,
                amountFlashLoan: flashLoan,
                swapData: swap,
                minTokenOut: 0
            })
        );
        vm.stopPrank();

        assertEq(collateralToken.balanceOf(alice), aliceBefore);
        assertEq(
            collateralToken.balanceOf(bob),
            bobBefore - INITIAL_COLLATERAL
        );
        assertEq(fl.getUserLeveragePositions(alice).length, 1);
    }

    // ─── Revert cases ───
    function test_leverage_revertsOnZeroAddressUser() external {
        fl.setApprovedOperator(alice, true);

        collateralToken.mint(alice, INITIAL_COLLATERAL);

        vm.startPrank(alice);
        collateralToken.approve(address(fl), INITIAL_COLLATERAL);

        vm.expectRevert(FLError.FlashLeverage__CannotBeZeroAddress.selector);
        fl.leverage(address(0), _dummyParams(correlatedMarketId));
        vm.stopPrank();
    }

    function test_leverage_revertsOnUnauthorizedCaller() external {
        vm.prank(bob);
        vm.expectRevert(FLError.FlashLeverage__NotApprovedOperator.selector);
        fl.leverage(alice, _dummyParams(correlatedMarketId));
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
                swapData: _emptySwap(),
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
                amountCollateral: INITIAL_COLLATERAL,
                amountFlashLoan: 0,
                swapData: _emptySwap(),
                minTokenOut: 0
            })
        );
    }

    function test_leverage_revertsOnUnsupportedMarket() external {
        vm.prank(alice);
        vm.expectRevert(FLError.FlashLeverage__UnsupportedMarket.selector);
        fl.leverage(alice, _dummyParams(keccak256("fake")));
    }

    function test_leverage_revertsOnDisabledMarket() external {
        fl.setMarketEnabled(correlatedMarketId, false);
        vm.prank(alice);
        vm.expectRevert(FLError.FlashLeverage__UnsupportedMarket.selector);
        fl.leverage(alice, _dummyParams(correlatedMarketId));
    }

    function test_leverage_revertsOnExceedingMaxLTV() external {
        uint256 aboveMaxLtv = fl.getMaxLtv(correlatedMarket) + 1e16;
        uint256 flashLoan = _calcFlashLoan(
            aboveMaxLtv,
            INITIAL_COLLATERAL,
            correlatedMarket
        );
        uint256 swapOut = _calcSwapOutput(flashLoan, correlatedMarket);
        SwapData memory swap = _buildSwapData(
            address(loanToken),
            address(collateralToken),
            flashLoan,
            swapOut
        );

        collateralToken.mint(alice, INITIAL_COLLATERAL);
        vm.startPrank(alice);
        collateralToken.approve(address(fl), INITIAL_COLLATERAL);
        vm.expectRevert();
        fl.leverage(
            alice,
            LeverageParams({
                marketId: correlatedMarketId,
                amountCollateral: INITIAL_COLLATERAL,
                amountFlashLoan: flashLoan,
                swapData: swap,
                minTokenOut: 0
            })
        );
        vm.stopPrank();
    }

    // ─── Internal helpers ───

    function _leverageAsAlice(
        uint256 collateral,
        uint256 targetLtv,
        MarketParams memory mkt,
        bytes32 mktId
    ) internal {
        uint256 flashLoan = _calcFlashLoan(targetLtv, collateral, mkt);
        uint256 swapOut = _calcSwapOutput(flashLoan, mkt);
        SwapData memory swap = _buildSwapData(
            mkt.loanToken,
            mkt.collateralToken,
            flashLoan,
            swapOut
        );

        vm.startPrank(alice);
        MockERC20(mkt.collateralToken).approve(address(fl), collateral);
        fl.leverage(
            alice,
            LeverageParams({
                marketId: mktId,
                amountCollateral: collateral,
                amountFlashLoan: flashLoan,
                swapData: swap,
                minTokenOut: 0
            })
        );
        vm.stopPrank();
    }

    function _dummyParams(
        bytes32 mktId
    ) internal view returns (LeverageParams memory) {
        return
            LeverageParams({
                marketId: mktId,
                amountCollateral: INITIAL_COLLATERAL,
                amountFlashLoan: 5e18,
                swapData: _emptySwap(),
                minTokenOut: 0
            });
    }

    function _emptySwap() internal view returns (SwapData memory) {
        return SwapData({extRouter: address(router), extCalldata: ""});
    }
}
