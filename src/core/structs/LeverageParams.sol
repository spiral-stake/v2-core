// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import {SwapAggregator, SwapParams, SwapData, ApproxParams, LimitOrderData} from "../leverage/SwapAggregator.sol";

struct LeverageParams {
    address collateralToken;
    address loanToken;
    uint256 amountUserCollateral;
    ApproxParams approxParams;
    address pendleSwap;
    SwapData swapData;
    LimitOrderData limitOrderData;
}
