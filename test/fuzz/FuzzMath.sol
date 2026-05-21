// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {Math} from "src/core/libraries/Math.sol";

/// @notice Thin wrapper so internal Math functions are callable from tests.
contract MathWrapper {
    using Math for uint256;

    function mulDown(uint256 a, uint256 b) external pure returns (uint256) {
        return a.mulDown(b);
    }

    function divDown(uint256 a, uint256 b) external pure returns (uint256) {
        return a.divDown(b);
    }

    function scaleTo(uint256 amount, uint8 from, uint8 to) external pure returns (uint256) {
        return amount.scaleTo(from, to);
    }
}

/// @notice Fuzz tests for the Math library (mulDown, divDown, scaleTo).
contract FuzzMath is Test {
    MathWrapper public m;

    uint256 constant ONE = 1e18;

    function setUp() public {
        m = new MathWrapper();
    }

    // ─── mulDown ──────────────────────────────────────────────────────────────

    // In the safe range (b ≤ ONE so result ≤ a), no overflow in assertion.
    function testFuzz_mulDown_safeRange(uint256 a, uint256 b) external view {
        // Keep a in 128-bit range and b ≤ 1e18 so a*b ≤ a, no assertion overflow.
        a = bound(a, 0, type(uint128).max);
        b = bound(b, 0, ONE);
        uint256 result = m.mulDown(a, b);
        // mulDown floors, so result ≤ a (since b ≤ ONE means b/ONE ≤ 1)
        assertLe(result, a);
    }

    // mulDown is commutative
    function testFuzz_mulDown_commutative(uint256 a, uint256 b) external view {
        a = bound(a, 0, type(uint128).max);
        b = bound(b, 0, type(uint128).max);
        assertEq(m.mulDown(a, b), m.mulDown(b, a));
    }

    // mulDown(a, ONE) == a (identity)
    function testFuzz_mulDown_identity(uint256 a) external view {
        a = bound(a, 0, type(uint128).max);
        assertEq(m.mulDown(a, ONE), a);
    }

    // mulDown is monotone: if a1 ≤ a2 then mulDown(a1,b) ≤ mulDown(a2,b)
    function testFuzz_mulDown_monotone(uint256 a1, uint256 a2, uint256 b) external view {
        a1 = bound(a1, 0, type(uint128).max / 2);
        a2 = bound(a2, a1, type(uint128).max);
        b  = bound(b,  0, type(uint128).max);
        assertLe(m.mulDown(a1, b), m.mulDown(a2, b));
    }

    // mulDown(0, any) == 0
    function testFuzz_mulDown_zeroIsAbsorbing(uint256 b) external view {
        b = bound(b, 0, type(uint128).max);
        assertEq(m.mulDown(0, b), 0);
        assertEq(m.mulDown(b, 0), 0);
    }

    // ─── divDown ─────────────────────────────────────────────────────────────

    // Safe range: a < type(uint256).max / 1e18 so a * 1e18 does not overflow.
    uint256 constant DIV_SAFE_MAX = type(uint256).max / 1e18;

    function testFuzz_divDown_safeRange(uint256 a, uint256 b) external view {
        a = bound(a, 0, DIV_SAFE_MAX);
        b = bound(b, 1, type(uint256).max); // b == 0 is division-by-zero, tested separately
        uint256 result = m.divDown(a, b);
        // floor property: result * b <= a * ONE
        // Both sides are within uint256 if result and b are bounded
        if (result <= DIV_SAFE_MAX && b <= DIV_SAFE_MAX) {
            assertLe(result * b, a * ONE);
        }
    }

    // divDown(a, a) == ONE for any non-zero a in safe range (a/a = 1)
    function testFuzz_divDown_selfDivEqualsOne(uint256 a) external view {
        a = bound(a, 1, DIV_SAFE_MAX);
        assertEq(m.divDown(a, a), ONE);
    }

    // divDown(a, ONE) == a (identity)
    function testFuzz_divDown_identityDivisor(uint256 a) external view {
        a = bound(a, 0, DIV_SAFE_MAX);
        assertEq(m.divDown(a, ONE), a);
    }

    // Division by zero reverts
    function testFuzz_divDown_zeroDivisorReverts(uint256 a) external {
        a = bound(a, 0, DIV_SAFE_MAX);
        vm.expectRevert();
        m.divDown(a, 0);
    }

    // Overflow: a > DIV_SAFE_MAX causes a * ONE to overflow → revert
    function testFuzz_divDown_overflowReverts(uint256 a) external {
        a = bound(a, DIV_SAFE_MAX + 1, type(uint256).max);
        vm.expectRevert();
        m.divDown(a, 1);
    }

    // ─── scaleTo ─────────────────────────────────────────────────────────────

    // Identity: scaleTo(x, d, d) == x
    function testFuzz_scaleTo_identity(uint256 amount, uint8 decimals) external view {
        decimals = uint8(bound(decimals, 0, 36));
        assertEq(m.scaleTo(amount, decimals, decimals), amount);
    }

    // Scale up then down is lossless (amount * 10^step / 10^step == amount)
    function testFuzz_scaleTo_upThenDown(uint256 amount, uint8 step) external view {
        step = uint8(bound(step, 1, 18));
        // Cap amount so upscale doesn't overflow
        uint256 cap = type(uint256).max / (10 ** step);
        amount = bound(amount, 0, cap);

        uint256 scaled = m.scaleTo(amount, 18, 18 + step);
        uint256 restored = m.scaleTo(scaled, 18 + step, 18);
        assertEq(restored, amount);
    }

    // Downscaling loses the truncated fractional digits
    function testFuzz_scaleTo_downLosesPrecision(uint256 amount, uint8 step) external view {
        step = uint8(bound(step, 1, 18));
        amount = bound(amount, 0, type(uint128).max);

        uint256 scaled = m.scaleTo(amount, 18 + step, 18);
        // Original reconstructed from scaled is always <= original
        uint256 reconstructed = scaled * (10 ** step);
        assertLe(reconstructed, amount);
        // Precision loss is bounded by 10^step - 1
        assertLe(amount - reconstructed, (10 ** step) - 1);
    }
}
