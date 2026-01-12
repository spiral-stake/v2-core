// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

/// @notice Custom errors for FlashLeverage protocol
library FLError {
    // Input validation
    error FlashLeverage__CannotBeZeroAddress();
    error FlashLeverage__AmountCannotBeZero();

    // Access / Security
    error FlashLeverage__UntrustedLender(); // Flashloan callback from non-Morpho address

    // Position management
    error FlashLeverage__ExceedsMaxLTV(); // desiredLtv > (liquidationLTV - buffer)
    error FlashLeverage__PositionAlreadyClosed();

    // Configuration
    error FlashLeverage__UnsupportedCollateralToken(); // Market not registered for token pair
    error FlashLeverage__InvalidCollateralToken(); // Mismatch between config and Morpho market
    error FlashLeverage__InvalidYieldFee(); // Fee is 0 or exceeds MAX_YIELD_FEE

    // Ownership
    error FlashLeverage__OwnershipRenunciationDisabled();
}
