// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

/// @notice Config for registering supported morphoMarkets via `addSupportedCollateralTokens()`
struct MarketConfig {
    bytes32 marketId;
    bool isCorrelated;
}
