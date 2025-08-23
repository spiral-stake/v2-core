// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

struct CoreLeveragePosition {
    uint256 amountCollateral; // (Leveraged)
    uint256 sharesBorrowed;
}
