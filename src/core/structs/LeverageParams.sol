// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import {SwapData, ApproxParams, LimitOrderData} from "@pendle/core-v2/contracts/interfaces/IPAllActionV3.sol";

struct LeverageParams {
    uint256 desiredLtv;
    address collateralToken;
    address loanToken;
    uint256 amountCollateral;
    ApproxParams approxParams;
    address pendleSwap;
    address tokenMintSy;
    uint256 minPtOut;
    SwapData swapData;
    LimitOrderData limitOrderData;
}

struct UnleverageParams {
    uint256 desiredLtv;
    address collateralToken;
    address loanToken;
    uint256 sharesToBurn;
    uint256 amountCollateralToWithdraw;
    address pendleSwap;
    address tokenRedeemSy;
    uint256 minTokenOut;
    SwapData swapData;
    LimitOrderData limitOrderData;
}
