// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import {SwapData, ApproxParams, LimitOrderData} from "@pendle/core-v2/contracts/interfaces/IPAllActionV3.sol";

struct LeverageParams {
    uint256 desiredLtv;
    address collateralToken;
    address loanToken;
    uint256 amountCollateral;
    SwapData swapData;
    uint256 minTokenOut;
    // Pendle Specific
    address pendleSwap;
    ApproxParams approxParams;
    address tokenMintSy;
    LimitOrderData limitOrderData;
}

struct DeleverageParams {
    SwapData swapData;
    uint256 minTokenOut;
    // Pendle Specific
    address pendleSwap;
    address tokenRedeemSy;
    LimitOrderData limitOrderData;
}
