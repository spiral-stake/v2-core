// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

/**
 * @notice Leverage Position
 */

struct LeveragePosition {
    bool open;
    address collateralToken;
    address loanToken;
    uint256 amountCollateral;
    uint256 amountCollateralInLoanToken;
    uint256 amountLeveragedCollateral;
    uint256 sharesBorrowed;
    uint256 positionValueInLoanToken;
}
