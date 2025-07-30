// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import {SwapData, ApproxParams, LimitOrderData} from "@pendle/core-v2/contracts/interfaces/IPAllActionV3.sol";

/**
 * @notice Parameters required for executing a leveraged position
 * @param tokenIn The input token provided by the user
 * @param amountTokenIn Amount of input tokens to use
 * @param minOut Minimum amount of tokens expected from swap
 * @param approxParams Parameters for approximation algorithms in Pendle
 * @param pendleSwap Address of the Pendle swap router
 * @param swapData Encoded swap data for token routing
 * @param limitOrderData Parameters for limit order execution
 */
struct SwapParams {
    address tokenIn;
    uint256 amountTokenIn;
    uint256 minOut;
    ApproxParams approxParams;
    address pendleSwap;
    address tokenMintSy;
    SwapData swapData;
    LimitOrderData limitOrderData;
}
