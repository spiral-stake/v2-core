// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

/**
 * @notice Leverage Position
 */

struct CollateralTokenConfig {
    address token;
    bytes32 morphoMarketId;
    address underlyingToken;
    address pendleMarket;
}
