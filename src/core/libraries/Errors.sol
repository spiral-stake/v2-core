// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

library Errors {
    /////////////////////////
    // StblUSD

    error StblUSD__CallerNotAManagerAddress();

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
    error PositionManager__InvalidFlashLoanToken();
    error PositionManager__AmountCannotBeZero();
    error PositionManager__InvalidReceiverAddress();
    error PositionManager__NotThePositionOwner();
    error PositionManager__CannotBeZeroAddress();

    /////////////////////////
    // FlashLeverage

    error FlashLeverage__UntrustedLender();
    error FlashLeverage__UntrustedLoanInitiator();
    error FlashLeverage__InvalidLoanToken();
    error FlashLeverage__InvalidLoanAmount();
    error FlashLeverage__ExceedsMaxLTV();
    error FlashLeverage__ExceedsMaxLeverageLTV();
    error FlashLeverage__InsufficientCollateralToUnleverage();
    error FlashLeverage__NotThePositionOwner();
}
