// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

library Error {
    error FlashLeverage__InvalidAmountCollateral();
    error FlashLeverage__UnsupportedCollateralToken();
    error FlashLeverage__UntrustedLender();
    error FlashLeverage__PositionDoesNotExist();
    error FlashLeverage__PositionAlreadyUnleveraged();
}
