// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import {SwapData, ApproxParams, LimitOrderData} from "@pendle/core-v2/contracts/interfaces/IPAllActionV3.sol";

/// @notice Parameters for opening a leveraged position
struct LeverageParams {
    uint256 desiredLtv; // Target loan-to-value ratio (18 decimals), must be <= maxLtv, used to calc flashLeverage loan when opening a position
    address collateralToken;
    address loanToken;
    uint256 amountCollateral;
    SwapData swapData; // Routing data for loanToken -> collateralToken swap
    uint256 minTokenOut; // Slippage protection: minimum collateral tokens received from swap
    // Pendle specific (ignored if collateralToken is not a pendle PT)
    address pendleSwap;
    ApproxParams approxParams; // Optional, for better gas eficiency
    address tokenMintSy; // Intermediate token for minting SY before PT swap
    LimitOrderData limitOrderData; // Optional
}

/// @notice Parameters for closing a leveraged position
struct DeleverageParams {
    SwapData swapData; // Routing data for collateralToken -> loanToken swap
    uint256 minTokenOut; // Slippage protection: minimum loan tokens received from swap
    // Pendle specific (ignored if collateralToken is not a pendle PT)
    address pendleSwap;
    address tokenRedeemSy; // Token received when redeeming SY after PT swap
    LimitOrderData limitOrderData; // Optional
}
