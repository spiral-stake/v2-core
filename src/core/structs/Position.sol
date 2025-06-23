// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

/**
 * @notice Position is short for Debt Position or Collateral Debt Position
 */

struct Position {
    address owner;
    address collateralToken;
    uint256 collateralDeposited;
    uint256 stblUSDMinted;
    // uint256 borrowApy;
    // uint256 maturity;
}
