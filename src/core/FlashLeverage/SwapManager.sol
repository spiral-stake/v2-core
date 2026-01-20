// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

/**
 * @title SwapAggregator
 * @notice SwapAggregator is the contract that facilatates the token swaps via swap aggregator(s)
 */

import {SwapData} from "../structs/SwapData.sol";
import {TokenHelper} from "../libraries/TokenHelper.sol";

contract SwapManager is TokenHelper {
    /////////////////////////
    // Storage

    // List of swap router contracts from swap aggregators like kyberswap, odos and pendle router
    mapping(address => bool) private s_isSwapRouter;

    function _swapToken(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        SwapData memory swapData,
        uint256 minTokenOut
    ) internal returns (uint256 amountOut) {
        require(s_isSwapRouter[swapData.extRouter], "Unsupported Swap Router");
        uint256 balanceBefore = _selfBalance(tokenOut);

        _forceApprove(tokenIn, address(swapData.extRouter), amountIn);
        (bool success, ) = swapData.extRouter.call(swapData.extCalldata);
        require(success, "Swap Router Call Failed");

        amountOut = _selfBalance(tokenOut) - balanceBefore;
        require(amountOut >= minTokenOut, "minTokenOut Not Met");
    }

    function _addSwapRouter(address router) internal {
        s_isSwapRouter[router] = true;
    }

    function _removeSwapRouter(address router) internal {
        s_isSwapRouter[router] = false;
    }

    function isValidSwapRouter(address router) external view returns (bool) {
        return s_isSwapRouter[router];
    }
}
