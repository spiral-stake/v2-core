// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import {SwapData} from "./SwapData.sol";

/// @notice Parameters for opening a leveraged position
struct LeverageParams {
    address collateralToken;
    address loanToken;
    uint256 amountCollateral;
    uint256 amountFlashLoan;
    SwapData swapData; // Routing data for loanToken -> collateralToken swap
    uint256 minTokenOut; // Slippage protection: minimum collateral tokens received from swap
}
