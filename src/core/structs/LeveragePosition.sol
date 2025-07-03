// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

/**
 * @notice Leverage Position
 */

struct LevPosition {
    address owner;
    uint256 debtPositionId;
    uint256 userCollateralDeposited;
}

struct LeveragePosition {
    address collateralToken;
    uint256 amountUserCollateral;
    uint256 ltv; // Needs to change
}
