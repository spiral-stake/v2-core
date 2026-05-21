// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import {FuzzTestBase} from "test/fuzz/FuzzTestBase.sol";
import {FLError} from "src/core/libraries/Error.sol";
import {Math} from "src/core/libraries/Math.sol";
import {LeverageParams} from "src/core/structs/LeverageParams.sol";
import {LeveragePosition} from "src/core/structs/LeveragePosition.sol";
import {SwapData} from "src/core/structs/SwapData.sol";
import {Position} from "@morpho/interfaces/IMorpho.sol";

/// @notice Fuzz tests for FlashLeverage::leverage, deleverage, and increaseLeverage.
contract FuzzLeverage is FuzzTestBase {
    using Math for uint256;

    // Caps chosen so flash-loan amounts stay within the 1M-token Morpho liquidity pool.
    // Correlated: 1 collateral ≈ 1.1 loan; at maxLtv 92% → flashLoan ≈ 11.5 × collateral value.
    // 50_000 × 1.1 × 11.5 ≈ 632k WETH < 1M.
    // Non-correlated: 1 ETH = 2000 USDC; at maxLtv 83.5% → flashLoan per ETH ≈ 10k USDC.
    // 50 ETH → 500k USDC < 1M.
    uint256 constant MIN_COLLATERAL = 1e15;
    uint256 constant MAX_CORR_COLLATERAL = 50_000e18;
    uint256 constant MAX_NC_COLLATERAL = 50e18;
    uint256 constant MIN_LTV = 5e16; // 5%

    // ─── leverage: valid paths ─────────────────────────────────────────────────

    function testFuzz_leverage_validCorrelated(uint256 collateral, uint256 ltvSeed) external {
        collateral = bound(collateral, MIN_COLLATERAL, MAX_CORR_COLLATERAL);
        uint256 maxLtv = fl.getMaxLtv(correlatedMarket);
        uint256 ltv = bound(ltvSeed, MIN_LTV, maxLtv - 1e14);

        uint256 flashLoan = _calcFlashLoan(ltv, collateral, correlatedMarket);
        uint256 swapOut = _calcSwapOutput(flashLoan, correlatedMarket);
        SwapData memory swap = _buildSwapData(
            address(loanToken), address(collateralToken), flashLoan, swapOut
        );

        collateralToken.mint(alice, collateral);
        vm.startPrank(alice);
        collateralToken.approve(address(fl), collateral);
        fl.leverage(alice, LeverageParams({
            marketId: correlatedMarketId,
            amountCollateral: collateral,
            amountFlashLoan: flashLoan,
            swapData: swap,
            minTokenOut: 0
        }));
        vm.stopPrank();

        LeveragePosition memory pos = fl.getUserLeveragePosition(alice, 0);
        assertTrue(pos.open);
        assertGt(pos.amountDepositedInLoanToken, 0);
        assertEq(pos.amountReturnedInLoanToken, 0);
        assertTrue(pos.userProxy != address(0));
        // No tokens stranded in the contract
        assertEq(collateralToken.balanceOf(address(fl)), 0);
        assertEq(loanToken.balanceOf(address(fl)), 0);
    }

    function testFuzz_leverage_validNonCorrelated(uint256 collateral, uint256 ltvSeed) external {
        collateral = bound(collateral, MIN_COLLATERAL, MAX_NC_COLLATERAL);
        uint256 maxLtv = fl.getMaxLtv(nonCorrelatedMarket);
        uint256 ltv = bound(ltvSeed, MIN_LTV, maxLtv - 1e14);

        uint256 posId = _openNonCorrelatedPosition(alice, collateral, ltv);
        LeveragePosition memory pos = fl.getUserLeveragePosition(alice, posId);

        assertTrue(pos.open);
        assertEq(pos.marketId, nonCorrelatedMarketId);
        assertTrue(pos.userProxy != address(0));
        assertEq(ncCollateralToken.balanceOf(address(fl)), 0);
        assertEq(ncLoanToken.balanceOf(address(fl)), 0);
    }

    // No tokens left in FlashLeverage after leverage — checked separately for correlated+NC
    function testFuzz_leverage_noTokensStranded(uint256 collateral, uint256 ltvSeed) external {
        collateral = bound(collateral, MIN_COLLATERAL, MAX_CORR_COLLATERAL);
        uint256 maxLtv = fl.getMaxLtv(correlatedMarket);
        uint256 ltv = bound(ltvSeed, MIN_LTV, maxLtv - 1e14);

        _openCorrelatedPosition(alice, collateral, ltv);

        assertEq(collateralToken.balanceOf(address(fl)), 0);
        assertEq(loanToken.balanceOf(address(fl)), 0);
    }

    // ─── leverage: access control ──────────────────────────────────────────────

    function testFuzz_leverage_zeroUserReverts(uint256 collateral, uint256 flashLoan) external {
        collateral = bound(collateral, 1, type(uint128).max);
        flashLoan = bound(flashLoan, 1, type(uint128).max);

        fl.setApprovedOperator(alice, true);
        vm.prank(alice);
        vm.expectRevert(FLError.FlashLeverage__CannotBeZeroAddress.selector);
        fl.leverage(address(0), LeverageParams({
            marketId: correlatedMarketId,
            amountCollateral: collateral,
            amountFlashLoan: flashLoan,
            swapData: SwapData({extRouter: address(router), extCalldata: ""}),
            minTokenOut: 0
        }));
    }

    function testFuzz_leverage_unauthorizedCallerReverts(address caller) external {
        vm.assume(caller != address(0));
        vm.assume(caller != alice);
        vm.assume(!fl.s_approvedOperators(caller));

        vm.prank(caller);
        vm.expectRevert(FLError.FlashLeverage__NotApprovedOperator.selector);
        fl.leverage(alice, LeverageParams({
            marketId: correlatedMarketId,
            amountCollateral: 1e18,
            amountFlashLoan: 1e18,
            swapData: SwapData({extRouter: address(router), extCalldata: ""}),
            minTokenOut: 0
        }));
    }

    // ─── leverage: LTV enforcement ─────────────────────────────────────────────

    function testFuzz_leverage_ltvTooHighReverts(uint256 collateral, uint256 ltvExcess) external {
        collateral = bound(collateral, MIN_COLLATERAL, 1_000e18);
        uint256 maxLtv = fl.getMaxLtv(correlatedMarket);
        // Fuzz an LTV strictly above maxLtv
        uint256 ltv = maxLtv + bound(ltvExcess, 1e14, 5e16);

        uint256 flashLoan = _calcFlashLoan(ltv, collateral, correlatedMarket);
        uint256 swapOut = _calcSwapOutput(flashLoan, correlatedMarket);
        SwapData memory swap = _buildSwapData(
            address(loanToken), address(collateralToken), flashLoan, swapOut
        );

        collateralToken.mint(alice, collateral);
        vm.startPrank(alice);
        collateralToken.approve(address(fl), collateral);
        vm.expectRevert();
        fl.leverage(alice, LeverageParams({
            marketId: correlatedMarketId,
            amountCollateral: collateral,
            amountFlashLoan: flashLoan,
            swapData: swap,
            minTokenOut: 0
        }));
        vm.stopPrank();
    }

    // ─── leverage: deposit fee (non-correlated) ────────────────────────────────

    function testFuzz_leverage_depositFeeOnNonCorrelated(uint256 collateral, uint256 feeSeed) external {
        collateral = bound(collateral, MIN_COLLATERAL, MAX_NC_COLLATERAL);
        // MAX_DEPOSIT_FEE = 1e16 (1%), zero is valid but produces no fee so start at 1 wei
        uint256 depositFee = bound(feeSeed, 1e14, 1e16);
        fl.updateDepositFee(depositFee);

        uint256 treasuryBefore = ncCollateralToken.balanceOf(treasury);
        _openNonCorrelatedPosition(alice, collateral, 40e16);

        uint256 fee = ncCollateralToken.balanceOf(treasury) - treasuryBefore;
        assertEq(fee, collateral.mulDown(depositFee));
    }

    function testFuzz_leverage_noDepositFeeOnCorrelated(uint256 collateral, uint256 feeSeed) external {
        collateral = bound(collateral, MIN_COLLATERAL, MAX_CORR_COLLATERAL);
        uint256 depositFee = bound(feeSeed, 1e14, 1e16);
        fl.updateDepositFee(depositFee);

        uint256 treasuryBefore = collateralToken.balanceOf(treasury);
        _openCorrelatedPosition(alice, collateral, 50e16);
        assertEq(collateralToken.balanceOf(treasury), treasuryBefore);
    }

    // ─── leverage: amount pulled from caller, not from user ───────────────────

    function testFuzz_leverage_operatorPayscollateral(uint256 collateral) external {
        collateral = bound(collateral, MIN_COLLATERAL, MAX_CORR_COLLATERAL);
        fl.setApprovedOperator(bob, true);

        collateralToken.mint(bob, collateral);
        uint256 flashLoan = _calcFlashLoan(50e16, collateral, correlatedMarket);
        uint256 swapOut = _calcSwapOutput(flashLoan, correlatedMarket);
        SwapData memory swap = _buildSwapData(
            address(loanToken), address(collateralToken), flashLoan, swapOut
        );

        uint256 aliceBefore = collateralToken.balanceOf(alice);
        uint256 bobBefore = collateralToken.balanceOf(bob);

        vm.startPrank(bob);
        collateralToken.approve(address(fl), collateral);
        fl.leverage(alice, LeverageParams({
            marketId: correlatedMarketId,
            amountCollateral: collateral,
            amountFlashLoan: flashLoan,
            swapData: swap,
            minTokenOut: 0
        }));
        vm.stopPrank();

        assertEq(collateralToken.balanceOf(alice), aliceBefore, "Alice balance unchanged");
        assertEq(collateralToken.balanceOf(bob), bobBefore - collateral, "Bob pays collateral");
        assertEq(fl.getUserLeveragePositions(alice).length, 1, "Position under Alice");
    }

    // ─── deleverage ────────────────────────────────────────────────────────────

    function testFuzz_deleverage_returnsFundsToUser(uint256 collateral, uint256 ltvSeed) external {
        collateral = bound(collateral, MIN_COLLATERAL, MAX_CORR_COLLATERAL);
        uint256 maxLtv = fl.getMaxLtv(correlatedMarket);
        uint256 ltv = bound(ltvSeed, MIN_LTV, maxLtv - 1e14);

        uint256 posId = _openCorrelatedPosition(alice, collateral, ltv);
        LeveragePosition memory pos = fl.getUserLeveragePosition(alice, posId);
        Position memory morphoPos = fl.getMorphoPosition(pos.userProxy, correlatedMarket);

        // Swap at oracle price: collateral -> loanToken
        uint256 swapOut = fl.getCollateralValueInLoanToken(correlatedMarket, morphoPos.collateral);
        SwapData memory swap = _buildSwapData(
            address(collateralToken), address(loanToken), morphoPos.collateral, swapOut
        );

        uint256 aliceBefore = loanToken.balanceOf(alice);
        vm.prank(alice);
        uint256 returned = fl.deleverage(posId, 0, swap, 0);

        assertFalse(fl.getUserLeveragePosition(alice, posId).open);
        assertEq(loanToken.balanceOf(alice), aliceBefore + returned);
        assertEq(collateralToken.balanceOf(address(fl)), 0);
        assertEq(loanToken.balanceOf(address(fl)), 0);
    }

    function testFuzz_deleverage_closedPositionReverts(uint256 collateral, uint256 ltvSeed) external {
        collateral = bound(collateral, MIN_COLLATERAL, 1_000e18);
        uint256 maxLtv = fl.getMaxLtv(correlatedMarket);
        uint256 ltv = bound(ltvSeed, MIN_LTV, maxLtv - 1e14);

        uint256 posId = _openCorrelatedPosition(alice, collateral, ltv);
        LeveragePosition memory pos = fl.getUserLeveragePosition(alice, posId);
        Position memory morphoPos = fl.getMorphoPosition(pos.userProxy, correlatedMarket);

        uint256 swapOut = fl.getCollateralValueInLoanToken(correlatedMarket, morphoPos.collateral);
        SwapData memory swap = _buildSwapData(
            address(collateralToken), address(loanToken), morphoPos.collateral, swapOut
        );

        vm.prank(alice);
        fl.deleverage(posId, 0, swap, 0);

        // Second call must revert
        vm.prank(alice);
        vm.expectRevert(FLError.FlashLeverage__PositionAlreadyClosed.selector);
        fl.deleverage(posId, 0, swap, 0);
    }

    function testFuzz_deleverage_exceedsCollateralReverts(
        uint256 collateral,
        uint256 ltvSeed,
        uint256 excess
    ) external {
        collateral = bound(collateral, MIN_COLLATERAL, 1_000e18);
        uint256 maxLtv = fl.getMaxLtv(correlatedMarket);
        uint256 ltv = bound(ltvSeed, MIN_LTV, maxLtv - 1e14);
        excess = bound(excess, 1, 1_000e18);

        uint256 posId = _openCorrelatedPosition(alice, collateral, ltv);
        LeveragePosition memory pos = fl.getUserLeveragePosition(alice, posId);
        Position memory morphoPos = fl.getMorphoPosition(pos.userProxy, correlatedMarket);

        uint256 tooMuch = morphoPos.collateral + excess;

        vm.prank(alice);
        vm.expectRevert(FLError.FlashLeverage__ExceedsCollateral.selector);
        fl.deleverage(
            posId, tooMuch, SwapData({extRouter: address(router), extCalldata: ""}), 0
        );
    }

    // ─── increaseLeverage ──────────────────────────────────────────────────────

    function testFuzz_increaseLeverage_closedPositionReverts(
        uint256 collateral,
        uint256 ltvSeed,
        uint256 increaseAmount
    ) external {
        collateral = bound(collateral, MIN_COLLATERAL, 1_000e18);
        uint256 maxLtv = fl.getMaxLtv(correlatedMarket);
        uint256 ltv = bound(ltvSeed, MIN_LTV, maxLtv - 1e14);
        increaseAmount = bound(increaseAmount, 1, 1e18);

        uint256 posId = _openCorrelatedPosition(alice, collateral, ltv);
        LeveragePosition memory pos = fl.getUserLeveragePosition(alice, posId);
        Position memory morphoPos = fl.getMorphoPosition(pos.userProxy, correlatedMarket);

        uint256 swapOut = fl.getCollateralValueInLoanToken(correlatedMarket, morphoPos.collateral);
        SwapData memory closeSwap = _buildSwapData(
            address(collateralToken), address(loanToken), morphoPos.collateral, swapOut
        );

        vm.prank(alice);
        fl.deleverage(posId, 0, closeSwap, 0);

        vm.prank(alice);
        vm.expectRevert(FLError.FlashLeverage__PositionAlreadyClosed.selector);
        fl.increaseLeverage(
            posId, increaseAmount,
            SwapData({extRouter: address(router), extCalldata: ""}),
            0
        );
    }

    function testFuzz_increaseLeverage_zeroAmountReverts(
        uint256 collateral,
        uint256 ltvSeed
    ) external {
        collateral = bound(collateral, MIN_COLLATERAL, 1_000e18);
        uint256 maxLtv = fl.getMaxLtv(correlatedMarket);
        uint256 ltv = bound(ltvSeed, MIN_LTV, maxLtv - 1e14);

        uint256 posId = _openCorrelatedPosition(alice, collateral, ltv);

        vm.prank(alice);
        vm.expectRevert(FLError.FlashLeverage__AmountCannotBeZero.selector);
        fl.increaseLeverage(
            posId, 0, SwapData({extRouter: address(router), extCalldata: ""}), 0
        );
    }
}
