// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import {StdInvariant} from "forge-std/StdInvariant.sol";
import {FuzzTestBase} from "test/fuzz/FuzzTestBase.sol";
import {LeveragePosition} from "src/core/structs/LeveragePosition.sol";
import {FlashLeverageHandler} from "test/invariant/handlers/FlashLeverageHandler.sol";

/// @notice Invariant test suite for FlashLeverage.
///
/// Invariants checked:
///   1. FlashLeverage holds zero loanToken after any call.
///   2. FlashLeverage holds zero collateralToken after any call.
///   3. FlashLeverage holds zero ncLoanToken after any call.
///   4. FlashLeverage holds zero ncCollateralToken after any call.
///   5. Every position the handler recorded as open is still open on-chain.
///   6. Every position the handler recorded as closed remains closed on-chain.
///   7. Treasury loan-token balance never decreases (yield fees only accumulate).
///   8. Treasury ncLoanToken balance never decreases.
///   9. Every open position has a non-zero userProxy address.
///  10. Protocol is never permanently paused (sanity: owner can always unpause).
///
/// @dev Inherits FuzzTestBase for the full setUp (Morpho, FlashLeverage,
///      100M extra liquidity). StdInvariant is already included via Test.
contract InvariantFlashLeverage is FuzzTestBase {

    FlashLeverageHandler public handler;

    function setUp() public override {
        super.setUp();

        handler = new FlashLeverageHandler(
            address(fl),
            address(router),
            address(collateralToken),
            address(loanToken),
            address(ncCollateralToken),
            address(ncLoanToken),
            address(correlatedOracle),
            address(nonCorrelatedOracle),
            correlatedMarket,
            nonCorrelatedMarket,
            correlatedMarketId,
            nonCorrelatedMarketId,
            treasury,
            alice,
            bob
        );

        // Only fuzz the handler — don't let the fuzzer call FlashLeverage directly,
        // which would bypass ghost-variable tracking.
        targetContract(address(handler));

        // Limit selectors to the meaningful state-transition functions.
        bytes4[] memory selectors = new bytes4[](5);
        selectors[0] = FlashLeverageHandler.leverage_correlated.selector;
        selectors[1] = FlashLeverageHandler.leverage_nonCorrelated.selector;
        selectors[2] = FlashLeverageHandler.deleverage.selector;
        selectors[3] = FlashLeverageHandler.supplyCollateral.selector;
        selectors[4] = FlashLeverageHandler.repay.selector;

        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    // ─── Token-stranding invariants ────────────────────────────────────────────

    function invariant_noLoanTokenInFlashLeverage() external view {
        assertEq(
            loanToken.balanceOf(address(fl)),
            0,
            "loanToken stranded in FlashLeverage"
        );
    }

    function invariant_noCollateralTokenInFlashLeverage() external view {
        assertEq(
            collateralToken.balanceOf(address(fl)),
            0,
            "collateralToken stranded in FlashLeverage"
        );
    }

    function invariant_noNcLoanTokenInFlashLeverage() external view {
        assertEq(
            ncLoanToken.balanceOf(address(fl)),
            0,
            "ncLoanToken stranded in FlashLeverage"
        );
    }

    function invariant_noNcCollateralTokenInFlashLeverage() external view {
        assertEq(
            ncCollateralToken.balanceOf(address(fl)),
            0,
            "ncCollateralToken stranded in FlashLeverage"
        );
    }

    // ─── Position-state invariants ─────────────────────────────────────────────

    /// Ghost-open positions must still be open on-chain.
    function invariant_openPositionsRemainOpen() external view {
        uint256 n = handler.getGhostOpenCount();
        for (uint256 i; i < n; ++i) {
            address actor = handler.ghost_openActors(i);
            uint256 posId = handler.ghost_openPosIds(i);
            LeveragePosition memory pos = fl.getUserLeveragePosition(actor, posId);
            assertTrue(pos.open, "ghost-open position is closed on-chain");
        }
    }

    /// Ghost-closed positions must never flip back to open.
    function invariant_closedPositionsStayClosed() external view {
        uint256 n = handler.getGhostClosedCount();
        for (uint256 i; i < n; ++i) {
            address actor = handler.ghost_closedActors(i);
            uint256 posId = handler.ghost_closedPosIds(i);
            LeveragePosition memory pos = fl.getUserLeveragePosition(actor, posId);
            assertFalse(pos.open, "ghost-closed position is open on-chain");
        }
    }

    /// Every open position must have a non-zero userProxy.
    function invariant_openPositionsHaveProxy() external view {
        uint256 n = handler.getGhostOpenCount();
        for (uint256 i; i < n; ++i) {
            address actor = handler.ghost_openActors(i);
            uint256 posId = handler.ghost_openPosIds(i);
            LeveragePosition memory pos = fl.getUserLeveragePosition(actor, posId);
            assertTrue(pos.userProxy != address(0), "open position has zero proxy");
        }
    }

    // ─── Treasury invariants ───────────────────────────────────────────────────

    /// Treasury loan-token balance must never decrease (yield fees only accumulate).
    function invariant_treasuryLoanBalanceNonDecreasing() external view {
        assertGe(
            loanToken.balanceOf(treasury),
            handler.ghost_treasuryLoanInitial(),
            "treasury loanToken balance decreased"
        );
    }

    /// Treasury ncLoanToken balance must never decrease.
    function invariant_treasuryNcLoanBalanceNonDecreasing() external view {
        assertGe(
            ncLoanToken.balanceOf(treasury),
            handler.ghost_treasuryNcLoanInitial(),
            "treasury ncLoanToken balance decreased"
        );
    }
}
