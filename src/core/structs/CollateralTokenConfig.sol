// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

/// @notice Config for registering supported collateral tokens via `addSupportedCollateralTokens()`
struct CollateralTokenConfig {
    address collateralToken;
    bytes32 morphoMarketId;
    bool isCorrelated;
}
