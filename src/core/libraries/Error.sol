// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

library FLCError {
    error FlashLeverageCore__UnsupportedCollateralToken();
    error FlashLeverageCore__AmountCannotBeZero();
    error FlashLeverageCore__UntrustedLender();
    error FlashLeverageCore__InsufficientSharesBorrowed();
    error FlashLeverageCore__InsufficientCollateralDeposited();
    error FlashLeverageCore__ExceedsMaxLTV();
    error FlashLeverageCore__RenounceOwnershipDisabled();
    error FlashLeverageCore__NotAManager();
    error FlashLeverageCore__InvalidCollateralToken();
    error FlashLeverageCore__InvalidCollateralTokenDecimals();
}

library FLError {
    error FlashLeverage__InvalidOnBehalfOfAddress();
    error FlashLeverage__InvalidAmountCollateral();
    error FlashLeverage__PositionDoesNotExist();
    error FlashLeverage__PositionAlreadyUnleveraged();
    error FlashLeverage__AmountCannotBeZero();
    error FlashLeverage__UnsupportedCollateralToken();
    error FlashLeverage__TreasuryCannotBeZero();
    error FlashLeverage__RenounceOwnershipDisabled();
}
