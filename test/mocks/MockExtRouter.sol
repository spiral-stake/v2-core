// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title MockExtRouter
/// @notice Simulates a DEX aggregator router for testing swap flows.
///         Must be pre-funded with tokenOut before the swap call.
contract MockExtRouter {
    using SafeERC20 for IERC20;

    /// @notice Execute a swap: pull tokenIn from sender, send tokenOut to sender
    /// @param tokenIn Address of the input token
    /// @param tokenOut Address of the output token
    /// @param amountIn Amount of tokenIn to pull from msg.sender
    /// @param amountOut Amount of tokenOut to send to msg.sender
    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOut
    ) external {
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        IERC20(tokenOut).safeTransfer(msg.sender, amountOut);
    }

    /// @notice Swap that accepts native ETH as input, refunds excess to sender
    /// @param tokenOut Address of the output token
    /// @param amountETHIn Actual amount of ETH to consume
    /// @param amountOut Amount of tokenOut to send to msg.sender
    function swapETH(
        address tokenOut,
        uint256 amountETHIn,
        uint256 amountOut
    ) external payable {
        require(msg.value >= amountETHIn, "MockExtRouter: insufficient ETH");
        IERC20(tokenOut).safeTransfer(msg.sender, amountOut);

        // Refund excess ETH to sender
        uint256 excess = msg.value - amountETHIn;
        if (excess > 0) {
            (bool success, ) = msg.sender.call{value: excess}("");
            require(success, "MockExtRouter: ETH refund failed");
        }
    }

    /// @notice Swap that sends output to a specific receiver (not msg.sender)
    /// @param tokenIn Address of the input token
    /// @param tokenOut Address of the output token
    /// @param amountIn Amount of tokenIn to pull
    /// @param amountOut Amount of tokenOut to send
    /// @param receiver Address to receive tokenOut
    function swapToReceiver(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        address receiver
    ) external {
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        IERC20(tokenOut).safeTransfer(receiver, amountOut);
    }

    /// @notice No-op call that succeeds without consuming any tokens
    function noop() external {}
}
