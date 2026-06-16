// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import {FuzzTestBase} from "test/fuzz/FuzzTestBase.sol";
import {FLError} from "src/core/libraries/Error.sol";
import {UserProxy} from "src/core/FlashLeverage/UserProxy.sol";
import {LeveragePosition} from "src/core/structs/LeveragePosition.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {Position} from "@morpho/interfaces/IMorpho.sol";

/// @notice Fuzz tests for UserProxy access control and state transitions.
contract FuzzUserProxy is FuzzTestBase {

    /// @dev Opens a position for alice and returns the deployed UserProxy.
    function _getAliceProxy() internal returns (UserProxy proxy) {
        uint256 posId = _openCorrelatedPosition(alice, 10e18, 50e16);
        LeveragePosition memory pos = fl.getUserLeveragePosition(alice, posId);
        proxy = UserProxy(pos.userProxy);
    }

    // ─── initialize ────────────────────────────────────────────────────────────

    // initialize can only be called once; a second call reverts regardless of who calls
    function testFuzz_initialize_cannotCallTwice(address secondUser) external {
        vm.assume(secondUser != address(0));
        UserProxy proxy = _getAliceProxy();

        // The proxy was already initialized with alice in _openCorrelatedPosition
        // A second initialize from FlashLeverage (owner of the proxy) must revert
        vm.prank(address(fl));
        vm.expectRevert(FLError.FlashLeverage__ProxyAlreadyInitialized.selector);
        proxy.initialize(secondUser);
    }

    // Only FlashLeverage can call initialize; any other caller is rejected
    function testFuzz_initialize_onlyFlashLeverageCanCall(address caller) external {
        // Deploy a fresh (uninitialized) proxy clone — use the implementation directly
        // since clones are initialized in the same tx
        UserProxy proxy = new UserProxy(address(fl), address(morpho));

        vm.assume(caller != address(fl));
        vm.prank(caller);
        vm.expectRevert(FLError.FlashLeverage__Unauthorised.selector);
        proxy.initialize(alice);
    }

    // ─── execute ──────────────────────────────────────────────────────────────

    // Arbitrary callers (not FlashLeverage, not the user) are rejected
    function testFuzz_execute_arbitraryCallerReverts(address caller) external {
        UserProxy proxy = _getAliceProxy();

        vm.assume(caller != address(fl));
        vm.assume(caller != proxy.s_user());

        vm.prank(caller);
        vm.expectRevert(FLError.FlashLeverage__Unauthorised.selector);
        proxy.execute(hex"");
    }

    // When manual mode is OFF, the user (alice) cannot call execute
    function testFuzz_execute_userRevertsWhenNotInManualMode() external {
        UserProxy proxy = _getAliceProxy();
        assertFalse(proxy.s_manualMode(), "Manual mode must be off initially");

        vm.prank(alice);
        vm.expectRevert(FLError.FlashLeverage__NotInManualMode.selector);
        proxy.execute(hex"");
    }

    // When manual mode is ON, FlashLeverage cannot call execute
    function testFuzz_execute_flashLeverageRevertsWhenManualMode() external {
        UserProxy proxy = _getAliceProxy();
        fl.enableManualMode(address(proxy));
        assertTrue(proxy.s_manualMode());

        vm.prank(address(fl));
        vm.expectRevert(FLError.FlashLeverage__ManualModeEnabled.selector);
        proxy.execute(hex"");
    }

    // ─── executeExternal ────────────────────────────────────────────────────────

    // Only s_user (alice) may call executeExternal, for any target/calldata
    function testFuzz_executeExternal_onlyUser(
        address caller,
        address target,
        bytes calldata data
    ) external {
        UserProxy proxy = _getAliceProxy();
        vm.assume(caller != alice);

        vm.prank(caller);
        vm.expectRevert(FLError.FlashLeverage__Unauthorised.selector);
        proxy.executeExternal(target, data);
    }

    // Morpho can never be the target — for any calldata (position-safety linchpin)
    function testFuzz_executeExternal_morphoAlwaysBlocked(bytes calldata data) external {
        UserProxy proxy = _getAliceProxy();

        vm.prank(alice);
        vm.expectRevert(FLError.FlashLeverage__CannotBeMorpho.selector);
        proxy.executeExternal(address(morpho), data);
    }

    // FlashLeverage can never be the target — for any calldata
    function testFuzz_executeExternal_flashLeverageAlwaysBlocked(bytes calldata data) external {
        UserProxy proxy = _getAliceProxy();

        vm.prank(alice);
        vm.expectRevert(FLError.FlashLeverage__Unauthorised.selector);
        proxy.executeExternal(address(fl), data);
    }

    // executeExternal by the user can never reduce the Morpho position, regardless
    // of which (non-Morpho, non-FL) target or calldata is used.
    function testFuzz_executeExternal_cannotReducePosition(
        address target,
        bytes calldata data
    ) external {
        UserProxy proxy = _getAliceProxy();
        vm.assume(target != address(morpho) && target != address(fl));
        vm.assume(target != address(vm)); // avoid cheatcode address

        Position memory before = fl.getMorphoPosition(address(proxy), correlatedMarket);

        vm.prank(alice);
        try proxy.executeExternal(target, data) {} catch {}

        Position memory afterPos = fl.getMorphoPosition(address(proxy), correlatedMarket);
        assertEq(afterPos.collateral, before.collateral, "collateral changed");
        assertEq(afterPos.borrowShares, before.borrowShares, "borrow changed");
        assertFalse(
            morpho.isAuthorized(address(proxy), target),
            "target became authorized"
        );
    }

    // ─── enableManualMode ─────────────────────────────────────────────────────

    // Only FlashLeverage can enable manual mode
    function testFuzz_enableManualMode_onlyFlashLeverage(address caller) external {
        UserProxy proxy = _getAliceProxy();
        vm.assume(caller != address(fl));

        vm.prank(caller);
        vm.expectRevert(FLError.FlashLeverage__Unauthorised.selector);
        proxy.enableManualMode();
    }

    // Manual mode is monotonic: once enabled it stays enabled
    function testFuzz_enableManualMode_isMonotonic() external {
        UserProxy proxy = _getAliceProxy();
        assertFalse(proxy.s_manualMode());

        fl.enableManualMode(address(proxy));
        assertTrue(proxy.s_manualMode());

        // Calling again does not revert (idempotent) but manual mode stays true
        fl.enableManualMode(address(proxy));
        assertTrue(proxy.s_manualMode());
    }

    // Only owner of FlashLeverage can call fl.enableManualMode
    function testFuzz_enableManualMode_nonOwnerReverts(address caller) external {
        vm.assume(caller != owner);
        UserProxy proxy = _getAliceProxy();

        vm.prank(caller);
        vm.expectRevert();
        fl.enableManualMode(address(proxy));
    }

    // ─── recover ──────────────────────────────────────────────────────────────

    // Only s_user (alice) can call recover
    function testFuzz_recover_onlyUserSucceeds(uint256 dustAmount) external {
        dustAmount = bound(dustAmount, 0, 1_000e18);
        UserProxy proxy = _getAliceProxy();

        // Send some tokens to the proxy (simulating a reward / accidental transfer)
        collateralToken.mint(address(proxy), dustAmount);

        uint256 aliceBefore = collateralToken.balanceOf(alice);
        vm.prank(alice);
        proxy.recover(address(collateralToken));

        assertEq(collateralToken.balanceOf(alice), aliceBefore + dustAmount);
        assertEq(collateralToken.balanceOf(address(proxy)), 0);
    }

    function testFuzz_recover_arbitraryCallerReverts(address caller) external {
        UserProxy proxy = _getAliceProxy();
        vm.assume(caller != proxy.s_user());

        collateralToken.mint(address(proxy), 1e18);

        vm.prank(caller);
        vm.expectRevert(FLError.FlashLeverage__Unauthorised.selector);
        proxy.recover(address(collateralToken));
    }

    // ─── immutable integrity ───────────────────────────────────────────────────

    // Proxy's immutables always point to the right contracts
    function testFuzz_proxy_immutablesNeverChange(uint256 collateralSeed) external {
        uint256 collateral = bound(collateralSeed, 1e15, 1_000e18);
        uint256 posId = _openCorrelatedPosition(alice, collateral, 50e16);

        LeveragePosition memory pos = fl.getUserLeveragePosition(alice, posId);
        UserProxy proxy = UserProxy(pos.userProxy);

        assertEq(proxy.i_flashLeverage(), address(fl));
        assertEq(proxy.i_morpho(), address(morpho));
    }
}
