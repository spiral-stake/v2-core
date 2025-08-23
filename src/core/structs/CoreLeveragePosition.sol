// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

struct CoreLeveragePosition {
    uint256 amountCollateral; // Amount collateral (Leveraged)
    uint256 sharesBorrowed; // Shares borrowed against it
}
