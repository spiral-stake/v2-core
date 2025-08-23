// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

/**
 * @notice Leverage Position
 */

struct LeveragePosition {
    bool open;
    address collateralToken;
    address loanToken;
    uint256 desiredLtv;
    uint256 amountCollateral;
    uint256 amountCollateralInLoanToken; // For yield tracking when closing
    uint256 positionValueInLoanToken; // For real-time yield tracking
    uint256 amountLeveragedCollateral; // Required when closing the position
    uint256 sharesBorrowed; // Required when closing the position
}
