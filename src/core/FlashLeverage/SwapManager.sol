// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

/**
 * @title SwapAggregator
 * @notice SwapAggregator is the contract that facilatates the token swaps via aggregator(s)
 * @dev Currently only using kyberswap
 */

import {TokenHelper} from "../libraries/TokenHelper.sol";

contract SwapManager is TokenHelper {
    address public immutable i_swapRouter; // Only kyberswap

    constructor(address swapRouter) {
        i_swapRouter = swapRouter;
    }

    function _swap(
        address tokenIn,
        uint256 amountIn,
        bytes memory swapData
    ) internal returns (uint256 returnAmount) {
        _forceApprove(tokenIn, address(i_swapRouter), amountIn);
        (bool success, bytes memory result) = i_swapRouter.call(swapData);
        require(success, "Swap router call failed");
        (returnAmount, ) = abi.decode(result, (uint256, uint256));
    }
}
