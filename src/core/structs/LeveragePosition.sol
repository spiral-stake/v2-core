// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

/**
 * @notice Leverage Position
 */

struct LeveragePosition {
    uint256 debtPositionId;
    uint256 userCollateralDeposited;
}
