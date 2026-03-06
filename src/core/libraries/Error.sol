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

    // Configuration
    error FlashLeverage__UnsupportedMarket();
    error FlashLeverage__InvalidYieldFee(); // Fee is 0 or exceeds MAX_YIELD_FEE
    error FlashLeverage__InvalidDepositFee(); // Fee is 0 or exceed MAX_DEPOSIT_FEE

    // Ownership
    error FlashLeverage__OwnershipRenunciationDisabled();

    // UserProxy
    error FlashLeverage__ProxyAlreadyInitialized();
    error FlashLeverage__Unauthorised();
    error FlashLeverage__NotInManualMode();
    error FlashLeverage__ProxyCallFailed();
    error FlashLeverage__ManualModeEnabled();

    // SwapManager
    error FlashLeverage__UnsupportedSwapRouter();
    error FlashLeverage__SwapRouterCallFailed();
    error FlashLeverage__MinTokenOutNotMet();
}
