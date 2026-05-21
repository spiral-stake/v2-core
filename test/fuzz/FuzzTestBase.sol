// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import {TestBase} from "test/TestBase.sol";

/// @notice Extended base for fuzz tests.
/// @dev Adds 100× more Morpho liquidity so that flash loans near maxLtv on
///      large collateral amounts don't exhaust the pool.  The root constraint
///      is that Morpho transfers flash-loan tokens to the caller BEFORE the
///      callback; the in-callback borrow draws from the remaining balance.
///      Both amounts equal the flash loan, so we need pool_balance > 2 × flashLoan.
///      With 100M tokens the pool comfortably covers the fuzz limits.
abstract contract FuzzTestBase is TestBase {
    uint256 constant EXTRA_LIQUIDITY      = 100_000_000e18; // 100M WETH
    uint256 constant EXTRA_NC_LIQUIDITY   = 100_000_000e6;  // 100M USDC

    function setUp() public virtual override {
        super.setUp();
        _seedLiquidity(correlatedMarket,    EXTRA_LIQUIDITY,    loanToken);
        _seedLiquidity(nonCorrelatedMarket, EXTRA_NC_LIQUIDITY, ncLoanToken);
    }
}
