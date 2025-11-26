// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

library FLError {
    // Common
    error FlashLeverage__CannotBeZeroAddress();
    error FlashLeverage__AmountCannotBeZero();

    // Specific
    error FlashLeverage__UntrustedLender();
    error FlashLeverage__ExceedsMaxLTV();
    error FlashLeverage__UnsupportedCollateralToken();
    error FlashLeverage__InvalidCollateralToken();
    error FlashLeverage__InvalidCollateralTokenDecimals();
    error FlashLeverage__InvalidYieldFee();
    error FlashLeverage__EffectiveLtvTooHigh(
        uint256 desiredLtv,
        uint256 effectiveLtv
    );
}
