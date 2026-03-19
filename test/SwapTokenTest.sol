// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import "./TestBase.sol";
import {FLError} from "src/core/libraries/Error.sol";

/// @title SwapTokenTest
/// @notice Tests for SwapManager::_swapToken behavior including
///         the full amountIn consumption requirement and router validation.
contract SwapTokenTest is TestBase {
    // ─── Router validation ───

    function test_swap_revertsOnUnwhitelistedRouter() external {
        address fakeRouter = makeAddr("fakeRouter");

        collateralToken.mint(alice, 10e18);
        vm.startPrank(alice);
        collateralToken.approve(address(fl), 10e18);

        vm.expectRevert(FLError.FlashLeverage__UnsupportedSwapRouter.selector);
        fl.leverage(
            alice,
            LeverageParams({
                marketId: correlatedMarketId,
                amountCollateral: 10e18,
                amountFlashLoan: 5e18,
                swapData: SwapData({extRouter: fakeRouter, extCalldata: ""}),
                minTokenOut: 0
            })
        );
        vm.stopPrank();
    }

    // ─── Full consumption ───

    function test_swap_partialConsumption_reverts() external {
        // Create a swap that only consumes half the input
        uint256 collateral = 10e18;
        uint256 flashLoan = 5e18;

        // Router will only consume 2.5e18 of the 5e18 input
        MockERC20(address(collateralToken)).mint(address(router), 3e18);
        SwapData memory partialSwap = SwapData({
            extRouter: address(router),
            extCalldata: abi.encodeCall(
                MockExtRouter.swap,
                (
                    address(loanToken),
                    address(collateralToken),
                    flashLoan / 2,
                    3e18
                )
            )
        });

        collateralToken.mint(alice, collateral);
        vm.startPrank(alice);
        collateralToken.approve(address(fl), collateral);

        vm.expectRevert(FLError.FlashLeverage__PartialSwapNotAllowed.selector);
        fl.leverage(
            alice,
            LeverageParams({
                marketId: correlatedMarketId,
                amountCollateral: collateral,
                amountFlashLoan: flashLoan,
                swapData: partialSwap,
                minTokenOut: 0
            })
        );
        vm.stopPrank();
    }

    function test_swap_noopRouter_reverts() external {
        uint256 collateral = 10e18;
        uint256 flashLoan = 1e18;

        // No-op call that doesn't consume any tokens
        SwapData memory noopSwap = SwapData({
            extRouter: address(router),
            extCalldata: abi.encodeCall(MockExtRouter.noop, ())
        });

        collateralToken.mint(alice, collateral);
        vm.startPrank(alice);
        collateralToken.approve(address(fl), collateral);

        vm.expectRevert(FLError.FlashLeverage__PartialSwapNotAllowed.selector);
        fl.leverage(
            alice,
            LeverageParams({
                marketId: correlatedMarketId,
                amountCollateral: collateral,
                amountFlashLoan: flashLoan,
                swapData: noopSwap,
                minTokenOut: 0
            })
        );
        vm.stopPrank();
    }

    // ─── MinTokenOut ───

    function test_swap_revertsOnMinTokenOutNotMet() external {
        uint256 collateral = 10e18;
        uint256 flashLoan = 5e18;
        uint256 swapOut = 1e18; // very low output

        SwapData memory swap = _buildSwapData(
            address(loanToken),
            address(collateralToken),
            flashLoan,
            swapOut
        );

        collateralToken.mint(alice, collateral);
        vm.startPrank(alice);
        collateralToken.approve(address(fl), collateral);

        vm.expectRevert(FLError.FlashLeverage__MinTokenOutNotMet.selector);
        fl.leverage(
            alice,
            LeverageParams({
                marketId: correlatedMarketId,
                amountCollateral: collateral,
                amountFlashLoan: flashLoan,
                swapData: swap,
                minTokenOut: 10e18 // require more than swap returns
            })
        );
        vm.stopPrank();
    }

    // ─── UserProxy cannot be swap router ───

    function test_setSwapRouter_revertsOnUserProxy() external {
        uint256 posId = _openCorrelatedPosition(alice, 10e18, 70e16);
        LeveragePosition memory pos = fl.getUserLeveragePosition(alice, posId);

        vm.expectRevert(FLError.FlashLeverage__CannotBeUserProxy.selector);
        fl.setSwapRouter(pos.userProxy, true);
    }
}
