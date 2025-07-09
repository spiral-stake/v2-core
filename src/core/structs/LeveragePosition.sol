// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

/**
 * @notice Leverage Position
 */

struct LeveragePosition {
    address collateralToken;
    address loanToken;
    uint256 amountUserCollateral;
    uint256 amountTotalCollateral;
    uint256 sharesBorrowed;
    bool open;
}
