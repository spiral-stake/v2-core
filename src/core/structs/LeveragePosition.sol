// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

/**
 * @notice Leverage Position
 */

struct LeveragePosition {
    bool open;
    uint256 desiredLtv;
    address collateralToken;
    address loanToken;
    uint256 amountCollateral;
    uint256 amountCollateralInLoanToken; // For yield tracking and fees
    uint256 amountLeveragedCollateral; // Required when closing the position
    uint256 sharesBorrowed; // Required when closing the position
}
