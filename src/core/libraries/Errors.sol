// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

library Errors {
    /////////////////////////
    // SPIUSD

    error SPIUSD__CallerNotAManagerAddress();
    error SPIUSD__AmountCannotBeZero();
    error SPIUSD__InvalidReceiverAddress();

    /////////////////////////
    // PositionManager

    error PositionManager__ValueCannotBeZero();
    error PositionManager__UnsupportedCollateralToken();
    error PositionManager__MintExceedsMaxLTV();
    error PositionManager__IsUnderLiqLTV();
    error PositionManager__HealthFactorIsOK();
    error PositionManager__InvalidTokenAddress();
    error PositionManager__InvalidPriceFeedAddress();
    error PositionManager__FlashMintCallbackFailed();
    error PositionManager__FlashMintNotRepaid();

    /////////////////////////
    // FlashLeverage

    error FlashLeverage__UntrustedLender();
    error FlashLeverage__UntrustedLoanInitiator();
    error FlashLeverage__InvalidLoanToken();
    error FlashLeverage__InvalidLoanAmount();
}
