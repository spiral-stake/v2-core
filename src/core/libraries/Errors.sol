// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

library Errors {
    /////////////////////////
    // SPIUSD

    error SPIUSD__CallerNotAManagerAddress();

    /////////////////////////
    // PositionManager

    error PositionManager__ValueCannotBeZero();
    error PositionManager__UnsupportedCollateralToken();
    error PositionManager__MintExceedsMaxLTV();
    error PositionManager__IsUnderLiqLTV();
    error PositionManager__HealthFactorIsOK();
    error PositionManager__InvalidTokenAddress();
    error PositionManager__InvalidPriceFeedAddress();
}
