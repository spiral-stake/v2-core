// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

struct LeverageParams {
    uint256 desiredLtv;
    address collateralToken;
    address loanToken;
    uint256 amountCollateral;
    bytes swapData;
    // Need to add more swap related verification params and verify in the _swap function
}
