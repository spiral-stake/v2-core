// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

struct LeveragePosition {
    bool open;
    address collateralToken;
    address loanToken;
    uint256 amountCollateral;
    uint256 amountLeveragedCollateral; // Required when closing the position
    uint256 sharesBorrowed; // Required when closing the position
    address userProxy; // Each Position is a separate proxy contract
    uint256 amountCollateralInLoanToken; // Required for yield tracking and fees
}
