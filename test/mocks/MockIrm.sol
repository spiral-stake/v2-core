// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import {MarketParams, Market} from "@morpho/interfaces/IMorpho.sol";
import {IIrm} from "@morpho/interfaces/IIrm.sol";

/// @title MockIrm
/// @notice Returns a zero borrow rate for testing purposes.
///         This means no interest accrues, keeping share-to-asset ratios 1:1.
contract MockIrm is IIrm {
    function borrowRate(
        MarketParams memory,
        Market memory
    ) external pure returns (uint256) {
        return 0;
    }

    function borrowRateView(
        MarketParams memory,
        Market memory
    ) external pure returns (uint256) {
        return 0;
    }
}
