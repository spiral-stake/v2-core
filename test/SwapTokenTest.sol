// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import "./TestBase.sol";
import {FLError} from "src/core/libraries/Error.sol";

/// @title SwapTokenTest
/// @notice Tests for SwapManager::_swapToken behavior including
///         full amountIn consumption, router validation, and slippage protection.
contract SwapTokenTest is TestBase {
    using Math for uint256;

    uint256 constant INITIAL_COLLATERAL = 10e18;
    uint256 constant STANDARD_LTV = 70e16; // 70%

    // ─── Happy path (tested via leverage) ───

    function test_swap_fullConsumption_exactOutput() external {
        uint256 flashLoan = 5e18;
        uint256 expectedSwapOut = _calcSwapOutput(flashLoan, correlatedMarket);

        SwapData memory swap = _buildSwapData(
            address(loanToken),
            address(collateralToken),
            flashLoan,
            expectedSwapOut
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

        // Verify router received the tokenIn
        assertEq(
            loanToken.balanceOf(address(router)),
            flashLoan,
            "Router should hold swapped tokenIn"
        );

        // Verify position collateral = user deposit + exact swap output
        LeveragePosition memory pos = fl.getUserLeveragePosition(alice, 0);
        Position memory morphoPos = fl.getMorphoPosition(
            pos.userProxy,
            correlatedMarket
        );
        assertEq(
            morphoPos.collateral,
            INITIAL_COLLATERAL + expectedSwapOut,
            "Collateral should be deposit + swap output"
        );
    }

    // ─── Router validation ───

    function test_swap_revertsOnUnwhitelistedRouter() external {
        address fakeRouter = makeAddr("fakeRouter");

        collateralToken.mint(alice, INITIAL_COLLATERAL);
        vm.startPrank(alice);
        collateralToken.approve(address(fl), INITIAL_COLLATERAL);

        vm.expectRevert(FLError.FlashLeverage__UnsupportedSwapRouter.selector);
        fl.leverage(
            alice,
            LeverageParams({
                marketId: correlatedMarketId,
                amountCollateral: INITIAL_COLLATERAL,
                amountFlashLoan: 5e18,
                swapData: SwapData({extRouter: fakeRouter, extCalldata: ""}),
                minTokenOut: 0
            })
        );
        vm.stopPrank();
    }

    // ─── Full consumption enforcement ───

    function test_swap_partialConsumption_reverts() external {
        uint256 flashLoan = 5e18;

        // Router only consumes half the input
        uint256 partialIn = flashLoan / 2;
        collateralToken.mint(address(router), 3e18);
        SwapData memory partialSwap = SwapData({
            extRouter: address(router),
            extCalldata: abi.encodeCall(
                MockExtRouter.swap,
                (address(loanToken), address(collateralToken), partialIn, 3e18)
            )
        });

        collateralToken.mint(alice, INITIAL_COLLATERAL);
        vm.startPrank(alice);
        collateralToken.approve(address(fl), INITIAL_COLLATERAL);

        vm.expectRevert(FLError.FlashLeverage__PartialSwapNotAllowed.selector);
        fl.leverage(
            alice,
            LeverageParams({
                marketId: correlatedMarketId,
                amountCollateral: INITIAL_COLLATERAL,
                amountFlashLoan: flashLoan,
                swapData: partialSwap,
                minTokenOut: 0
            })
        );
        vm.stopPrank();
    }

    function test_swap_noopRouter_reverts() external {
        SwapData memory noopSwap = SwapData({
            extRouter: address(router),
            extCalldata: abi.encodeCall(MockExtRouter.noop, ())
        });

        collateralToken.mint(alice, INITIAL_COLLATERAL);
        vm.startPrank(alice);
        collateralToken.approve(address(fl), INITIAL_COLLATERAL);

        vm.expectRevert(FLError.FlashLeverage__PartialSwapNotAllowed.selector);
        fl.leverage(
            alice,
            LeverageParams({
                marketId: correlatedMarketId,
                amountCollateral: INITIAL_COLLATERAL,
                amountFlashLoan: 1e18,
                swapData: noopSwap,
                minTokenOut: 0
            })
        );
        vm.stopPrank();
    }

    // ─── Slippage protection ───

    function test_swap_minTokenOut_reverts() external {
        uint256 flashLoan = 5e18;
        uint256 swapOut = 1e18; // low output

        SwapData memory swap = _buildSwapData(
            address(loanToken),
            address(collateralToken),
            flashLoan,
            swapOut
        );

        collateralToken.mint(alice, INITIAL_COLLATERAL);
        vm.startPrank(alice);
        collateralToken.approve(address(fl), INITIAL_COLLATERAL);

        uint256 highMinOut = 10e18; // expect way more than swap returns

        vm.expectRevert(FLError.FlashLeverage__MinTokenOutNotMet.selector);
        fl.leverage(
            alice,
            LeverageParams({
                marketId: correlatedMarketId,
                amountCollateral: INITIAL_COLLATERAL,
                amountFlashLoan: flashLoan,
                swapData: swap,
                minTokenOut: highMinOut
            })
        );
        vm.stopPrank();
    }

    function test_swap_minTokenOut_exactBoundary_passes() external {
        uint256 flashLoan = 5e18;
        uint256 exactSwapOut = _calcSwapOutput(flashLoan, correlatedMarket);

        SwapData memory swap = _buildSwapData(
            address(loanToken),
            address(collateralToken),
            flashLoan,
            exactSwapOut
        );

        collateralToken.mint(alice, INITIAL_COLLATERAL);
        vm.startPrank(alice);
        collateralToken.approve(address(fl), INITIAL_COLLATERAL);

        // minTokenOut == exactSwapOut — should pass exactly
        fl.leverage(
            alice,
            LeverageParams({
                marketId: correlatedMarketId,
                amountCollateral: INITIAL_COLLATERAL,
                amountFlashLoan: flashLoan,
                swapData: swap,
                minTokenOut: exactSwapOut
            })
        );
        vm.stopPrank();

        assertEq(fl.getUserLeveragePositions(alice).length, 1);
    }

    // ─── Swap output routing ───

    function test_swap_zeroOutput_revertsOnLTV() external {
        // Flash loan so large that user collateral alone can't cover LTV
        uint256 largeFlashLoan = 50e18;

        SwapData memory zeroOutSwap = SwapData({
            extRouter: address(router),
            extCalldata: abi.encodeCall(
                MockExtRouter.swap,
                (
                    address(loanToken),
                    address(collateralToken),
                    largeFlashLoan,
                    0
                )
            )
        });

        collateralToken.mint(alice, INITIAL_COLLATERAL);
        vm.startPrank(alice);
        collateralToken.approve(address(fl), INITIAL_COLLATERAL);

        vm.expectRevert();
        fl.leverage(
            alice,
            LeverageParams({
                marketId: correlatedMarketId,
                amountCollateral: INITIAL_COLLATERAL,
                amountFlashLoan: largeFlashLoan,
                swapData: zeroOutSwap,
                minTokenOut: 0
            })
        );
        vm.stopPrank();
    }

    function test_swap_outputToExternalReceiver_revertsOnLTV() external {
        uint256 largeFlashLoan = 50e18;
        uint256 swapOut = _calcSwapOutput(largeFlashLoan, correlatedMarket);
        address externalReceiver = makeAddr("externalReceiver");

        collateralToken.mint(address(router), swapOut);
        SwapData memory maliciousSwap = SwapData({
            extRouter: address(router),
            extCalldata: abi.encodeCall(
                MockExtRouter.swapToReceiver,
                (
                    address(loanToken),
                    address(collateralToken),
                    largeFlashLoan,
                    swapOut,
                    externalReceiver
                )
            )
        });

        collateralToken.mint(alice, INITIAL_COLLATERAL);
        vm.startPrank(alice);
        collateralToken.approve(address(fl), INITIAL_COLLATERAL);

        vm.expectRevert();
        fl.leverage(
            alice,
            LeverageParams({
                marketId: correlatedMarketId,
                amountCollateral: INITIAL_COLLATERAL,
                amountFlashLoan: largeFlashLoan,
                swapData: maliciousSwap,
                minTokenOut: 0
            })
        );
        vm.stopPrank();
    }

    // ─── Multiple swaps ───

    function test_swap_consecutiveSwaps_noStaleState() external {
        // First position
        _openCorrelatedPosition(alice, INITIAL_COLLATERAL, STANDARD_LTV);

        // Second position — different user, same router
        _openCorrelatedPosition(bob, INITIAL_COLLATERAL, 60e16);

        // Both should succeed — no stale approval or balance issues
        assertEq(fl.getUserLeveragePositions(alice).length, 1);
        assertEq(fl.getUserLeveragePositions(bob).length, 1);

        // FL should hold nothing
        assertEq(collateralToken.balanceOf(address(fl)), 0);
        assertEq(loanToken.balanceOf(address(fl)), 0);
    }
}
