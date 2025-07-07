// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

/**
 * @notice Swap Params to swap via pendle router
 */

struct SwapParams {
    address underlyingToken; // MintSY token
    address pendleMarket;
}
