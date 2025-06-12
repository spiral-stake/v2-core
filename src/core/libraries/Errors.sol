// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

library Errors {
    /////////////////////////
    // SPIUSD

    error SPIUSD__CallerNotAManagerAddress();

    /////////////////////////
    // VaultManager

    error VaultManager__ValueCannotBeZero();
    error VaultManager__UnsupportedCollateralToken();
    error VaultManager__MintExceedsMaxLTV();
    error VaultManager__IsUnderLiqLTV();
    error VaultManager__HealthFactorIsOK();
    error VaultManager__InvalidTokenAddress();
    error VaultManager__InvalidPriceFeedAddress();
}
