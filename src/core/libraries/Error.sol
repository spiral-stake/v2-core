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
    error FlashLeverage__ExceedsMaxLTV(uint256 effectiveLtv, uint256 maxLtv);
    error FlashLeverage__PositionAlreadyClosed();
    error FlashLeverage__CannotBorrowForCorrelatedPair();

    // Configuration
    error FlashLeverage__UnsupportedMarket();
    error FlashLeverage__InvalidYieldFee(); // Fee is 0 or exceeds MAX_YIELD_FEE
    error FlashLeverage__InvalidDepositFee(); // Fee is 0 or exceed MAX_DEPOSIT_FEE

    // Ownership
    error FlashLeverage__OwnershipRenunciationDisabled();
}
