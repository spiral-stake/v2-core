// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

// ─── How to run ───────────────────────────────────────────────────────────────
//   halmos --match-contract SymMath --forge-build-out abi --solver-timeout-assertion 60000
//
// Every check_ function is a symbolic proof: Halmos exhaustively searches
// ALL possible uint256 values satisfying the vm.assume preconditions and
// reports any counterexample. A clean run means the property is PROVEN.
//
// Critical context for a protocol handling billions:
//   - mulDown(a, b) = floor(a * b / 1e18).  The multiplication a*b is checked
//     (Solidity 0.8 default), so overflow reverts rather than wrapping silently.
//   - divDown(a, b) = floor(a * 1e18 / b).  The inflation a*1e18 is checked;
//     the division itself is unchecked, but div-by-zero still panics in 0.8.
//   - All fee calculations, LTV computations, and yield accruals pass through
//     these two functions — any silent error here corrupts all protocol math.
//
// NOTE: Uses native Solidity assert() and try/catch instead of Foundry
//       assertion cheat codes for Halmos 0.1.x compatibility.
// ─────────────────────────────────────────────────────────────────────────────

import {Test} from "forge-std/Test.sol";
import {Math} from "src/core/libraries/Math.sol";

/// @dev Thin public harness so Halmos can invoke internal library functions.
contract MathHarness {
    using Math for uint256;

    function mulDown(uint256 a, uint256 b) external pure returns (uint256) {
        return a.mulDown(b);
    }

    function divDown(uint256 a, uint256 b) external pure returns (uint256) {
        return a.divDown(b);
    }

    function scaleTo(
        uint256 amount,
        uint8 from,
        uint8 to
    ) external pure returns (uint256) {
        return amount.scaleTo(from, to);
    }
}

/// @title SymMath
/// @notice Symbolic proofs for the Math library.
///         Each property is stated in plain English above its function.
contract SymMath is Test {
    MathHarness h;

    uint256 constant ONE           = 1e18;
    uint256 constant UINT128_MAX   = type(uint128).max;
    uint256 constant UINT64_MAX    = type(uint64).max;
    uint256 constant DIV_SAFE_MAX  = type(uint256).max / 1e18;

    function setUp() public {
        h = new MathHarness();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // mulDown
    // ═══════════════════════════════════════════════════════════════════════

    /// PROPERTY: mulDown(a, 1e18) == a  (multiplicative identity)
    /// WHY: Every "multiply by 100%" operation must return the principal
    ///      exactly — used in fee accrual and LTV computation.
    function check_mulDown_identity(uint256 a) external view {
        vm.assume(a <= UINT128_MAX);
        assert(h.mulDown(a, ONE) == a);
    }

    /// PROPERTY: mulDown(a, b) == mulDown(b, a)  (commutativity)
    /// WHY: The protocol sometimes calls mulDown(fee, amount) and other times
    ///      mulDown(amount, fee). Both must give identical results.
    function check_mulDown_commutative(uint256 a, uint256 b) external view {
        vm.assume(a <= UINT128_MAX);
        vm.assume(b <= UINT128_MAX);
        assert(h.mulDown(a, b) == h.mulDown(b, a));
    }

    /// PROPERTY: mulDown(0, b) == 0 and mulDown(a, 0) == 0  (zero absorbing)
    /// WHY: A zero fee or zero amount must never produce a non-zero result.
    function check_mulDown_zeroAbsorbing(uint256 a) external view {
        vm.assume(a <= UINT128_MAX);
        assert(h.mulDown(0, a) == 0);
        assert(h.mulDown(a, 0) == 0);
    }

    /// PROPERTY: b ≤ 1e18  →  mulDown(a, b) ≤ a  (no inflation)
    /// WHY: Fee rates and LTV values are fractions of 1e18.
    ///      mulDown(principal, feeRate) must never exceed principal.
    ///      If it did, the protocol could charge more than deposited.
    function check_mulDown_noInflation(uint256 a, uint256 b) external view {
        vm.assume(a <= UINT128_MAX);
        vm.assume(b <= ONE);
        assert(h.mulDown(a, b) <= a);
    }

    /// PROPERTY: mulDown(a, b) * ONE ≤ a * b  (floor rounds DOWN, never up)
    /// WHY: If mulDown ever rounded up, the protocol could pay out more than
    ///      it accrued. We prove the floor guarantee holds for all safe inputs.
    function check_mulDown_floorProperty(uint256 a, uint256 b) external view {
        vm.assume(a <= UINT64_MAX);
        vm.assume(b <= UINT64_MAX);
        uint256 result = h.mulDown(a, b);
        // result ≤ floor(a*b / 1e18), so result * 1e18 ≤ a * b
        assert(result * ONE <= a * b);
    }

    /// PROPERTY: mulDown is monotone in a: a1 ≤ a2  →  mulDown(a1,b) ≤ mulDown(a2,b)
    /// WHY: Larger principal must produce a larger (or equal) fee.
    ///      Violation would mean larger positions are charged proportionally less.
    function check_mulDown_monotone(
        uint256 a1,
        uint256 a2,
        uint256 b
    ) external view {
        vm.assume(a1 <= UINT128_MAX / 2);
        vm.assume(a2 >= a1 && a2 <= UINT128_MAX);
        vm.assume(b <= UINT128_MAX);
        assert(h.mulDown(a1, b) <= h.mulDown(a2, b));
    }

    /// PROPERTY: a * b overflows (a > type(uint256).max / b)  →  mulDown REVERTS
    /// WHY: The protocol must NEVER produce a silently wrapped (corrupted) result.
    ///      Solidity 0.8 checked multiplication guarantees an explicit revert here.
    function check_mulDown_overflowReverts(uint256 a, uint256 b) external {
        vm.assume(b > 0);
        vm.assume(a > type(uint256).max / b); // a * b would overflow
        bool reverted;
        try h.mulDown(a, b) returns (uint256) {
            reverted = false;
        } catch {
            reverted = true;
        }
        assert(reverted);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // divDown
    // ═══════════════════════════════════════════════════════════════════════

    /// PROPERTY: divDown(a, 1e18) == a  (divisor identity)
    /// WHY: Dividing by 100% (= 1e18) must return the original value.
    function check_divDown_identity(uint256 a) external view {
        vm.assume(a <= DIV_SAFE_MAX);
        assert(h.divDown(a, ONE) == a);
    }

    /// PROPERTY: divDown(a, a) == 1e18 for all non-zero a in safe range
    /// WHY: Self-division represents "a / a = 1.0". Used when normalising
    ///      positions by their own value — must yield exactly ONE.
    function check_divDown_selfEqualsOne(uint256 a) external view {
        vm.assume(a > 0);
        vm.assume(a <= DIV_SAFE_MAX);
        assert(h.divDown(a, a) == ONE);
    }

    /// PROPERTY: divDown(a, 0) REVERTS for all a
    /// WHY: The unchecked block in divDown only skips overflow checks,
    ///      NOT division-by-zero. This proves div-by-zero still panics.
    function check_divDown_zeroDivisorReverts(uint256 a) external {
        vm.assume(a <= DIV_SAFE_MAX);
        bool reverted;
        try h.divDown(a, 0) returns (uint256) {
            reverted = false;
        } catch {
            reverted = true;
        }
        assert(reverted);
    }

    /// PROPERTY: a > DIV_SAFE_MAX  →  divDown(a, b) REVERTS for any b > 0
    /// WHY: a * 1e18 overflows uint256 when a > type(uint256).max / 1e18.
    ///      The checked multiplication guarantees an explicit revert — the
    ///      protocol CANNOT silently operate on corrupted inflated values.
    function check_divDown_inflationOverflowReverts(uint256 a) external {
        vm.assume(a > DIV_SAFE_MAX);
        bool reverted;
        try h.divDown(a, 1) returns (uint256) {
            reverted = false;
        } catch {
            reverted = true;
        }
        assert(reverted);
    }

    /// PROPERTY: divDown(a, b) * b ≤ a * 1e18  (floor rounds DOWN, never up)
    /// WHY: If divDown ever rounded up, a leveraged position's LTV calculation
    ///      could exceed the real value, allowing borrows past the actual limit.
    function check_divDown_floorProperty(uint256 a, uint256 b) external view {
        vm.assume(a <= UINT128_MAX);
        vm.assume(b > 0 && b <= UINT128_MAX);
        uint256 result = h.divDown(a, b);
        vm.assume(result <= UINT128_MAX); // prevent overflow in assertion arithmetic
        assert(result * b <= a * ONE);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // scaleTo
    // ═══════════════════════════════════════════════════════════════════════

    /// PROPERTY: scaleTo(x, d, d) == x  for any x and any decimal d ≤ 36
    /// WHY: Converting to the same decimal precision must be a no-op.
    ///      The non-correlated market uses 6-decimal USDC — a wrong identity
    ///      here would corrupt all cross-decimal accounting.
    function check_scaleTo_identity(uint256 amount, uint8 decimals) external view {
        vm.assume(decimals <= 36);
        assert(h.scaleTo(amount, decimals, decimals) == amount);
    }

    /// PROPERTY: scaleTo(scaleTo(x, 18, 18+step), 18+step, 18) == x
    ///           (scale-up then scale-down is lossless in the safe range)
    /// WHY: Flash loan amounts are scaled to 18 decimals internally and back
    ///      to loan-token decimals. Any rounding here creates dust that could
    ///      leave tokens stranded in the contract.
    function check_scaleTo_upThenDown(uint256 amount, uint8 step) external view {
        vm.assume(step >= 1 && step <= 18);
        uint256 cap = type(uint256).max / (10 ** uint256(step));
        vm.assume(amount <= cap);
        uint256 scaled   = h.scaleTo(amount, 18, 18 + step);
        uint256 restored = h.scaleTo(scaled, 18 + step, 18);
        assert(restored == amount);
    }

    /// PROPERTY: scaleTo(x, 18+step, 18) * 10^step ≤ x
    ///           (downscaling never reports more than original)
    /// WHY: A collateral amount reported as larger after downscaling would
    ///      allow withdrawing more than actually deposited.
    function check_scaleTo_downNeverExceedsOriginal(
        uint256 amount,
        uint8 step
    ) external view {
        vm.assume(step >= 1 && step <= 18);
        vm.assume(amount <= type(uint128).max);
        uint256 scaled = h.scaleTo(amount, 18 + step, 18);
        uint256 reconstructed = scaled * (10 ** uint256(step));
        assert(reconstructed <= amount);
    }
}
