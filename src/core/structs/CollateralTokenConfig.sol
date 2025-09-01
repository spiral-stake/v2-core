// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

struct CollateralTokenConfig {
    address collateralToken;
    bytes32 morphoMarketId;
    address pendleMarket;
}
