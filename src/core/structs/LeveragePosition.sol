// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

/// @notice Represents a user's leveraged position state
struct LeveragePosition {
    bool open;
    address collateralToken;
    address loanToken;
    uint256 amountCollateral;
    address userProxy; // Isolated proxy contract holding this position on Morpho
    uint256 amountDepositedInLoanToken; // Initial deposit valued in loanToken, used for yield/fee calc
    uint256 amountReturnedInLoanToken; // Total amount returned to the user in loanToken (principal + yield, minus fees)
}
