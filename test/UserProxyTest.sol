// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import "./TestBase.sol";
import {UserProxy} from "src/core/FlashLeverage/UserProxy.sol";
import {FLError} from "src/core/libraries/Error.sol";

/// @title UserProxyTest
/// @notice Tests for UserProxy contract: initialization, execute, manual mode, recover
contract UserProxyTest is TestBase {
    // ═══════════════════════════════════════════════
    //              INITIALIZATION
    // ═══════════════════════════════════════════════

    function test_implementation_isInitialized() external view {
        address impl = fl.i_userProxyImplementation();
        UserProxy proxy = UserProxy(impl);

        // Implementation should be initialized to FlashLeverage address
        assertEq(
            proxy.s_user(),
            address(fl),
            "Implementation should be initialized"
        );
    }

    function test_clone_initializesWithUser() external {
        uint256 posId = _openCorrelatedPosition(alice, 10e18, 70e16);
        LeveragePosition memory pos = fl.getUserLeveragePosition(alice, posId);

        UserProxy proxy = UserProxy(pos.userProxy);
        assertEq(proxy.s_user(), alice, "Proxy user should be alice");
        assertEq(
            proxy.i_flashLeverage(),
            address(fl),
            "Proxy flashLeverage should be FL"
        );
    }

    function test_clone_cannotReinitialize() external {
        uint256 posId = _openCorrelatedPosition(alice, 10e18, 70e16);
        LeveragePosition memory pos = fl.getUserLeveragePosition(alice, posId);

        UserProxy proxy = UserProxy(pos.userProxy);
        vm.expectRevert(
            FLError.FlashLeverage__ProxyAlreadyInitialized.selector
        );
        proxy.initialize(bob);
    }

    // ═══════════════════════════════════════════════
    //              EXECUTE
    // ═══════════════════════════════════════════════

    function test_execute_revertsForUnauthorized() external {
        uint256 posId = _openCorrelatedPosition(alice, 10e18, 70e16);
        LeveragePosition memory pos = fl.getUserLeveragePosition(alice, posId);

        UserProxy proxy = UserProxy(pos.userProxy);

        vm.prank(bob);
        vm.expectRevert(FLError.FlashLeverage__Unauthorised.selector);
        proxy.execute(hex"");
    }

    function test_execute_userCannotCallWithoutManualMode() external {
        uint256 posId = _openCorrelatedPosition(alice, 10e18, 70e16);
        LeveragePosition memory pos = fl.getUserLeveragePosition(alice, posId);

        UserProxy proxy = UserProxy(pos.userProxy);

        vm.prank(alice);
        vm.expectRevert(FLError.FlashLeverage__NotInManualMode.selector);
        proxy.execute(hex"");
    }

    // ═══════════════════════════════════════════════
    //              MANUAL MODE
    // ═══════════════════════════════════════════════

    function test_manualMode_userCanExecuteAfterEnabled() external {
        uint256 posId = _openCorrelatedPosition(alice, 10e18, 70e16);
        LeveragePosition memory pos = fl.getUserLeveragePosition(alice, posId);

        // Enable manual mode (owner only)
        fl.enableManualMode(pos.userProxy);

        UserProxy proxy = UserProxy(pos.userProxy);
        assertTrue(proxy.s_manualMode(), "Manual mode should be enabled");
    }

    function test_manualMode_flashLeverageBlocked() external {
        uint256 posId = _openCorrelatedPosition(alice, 10e18, 70e16);
        LeveragePosition memory pos = fl.getUserLeveragePosition(alice, posId);

        fl.enableManualMode(pos.userProxy);

        UserProxy proxy = UserProxy(pos.userProxy);

        // FlashLeverage (address(fl)) should be blocked
        vm.prank(address(fl));
        vm.expectRevert(FLError.FlashLeverage__ManualModeEnabled.selector);
        proxy.execute(hex"");
    }

    function test_manualMode_cannotBeEnabledByNonFlashLeverage() external {
        uint256 posId = _openCorrelatedPosition(alice, 10e18, 70e16);
        LeveragePosition memory pos = fl.getUserLeveragePosition(alice, posId);

        UserProxy proxy = UserProxy(pos.userProxy);

        vm.prank(alice);
        vm.expectRevert(FLError.FlashLeverage__Unauthorised.selector);
        proxy.enableManualMode();
    }

    // ═══════════════════════════════════════════════
    //              RECOVER
    // ═══════════════════════════════════════════════

    function test_recover_userCanRecoverTokens() external {
        uint256 posId = _openCorrelatedPosition(alice, 10e18, 70e16);
        LeveragePosition memory pos = fl.getUserLeveragePosition(alice, posId);

        // Send some tokens to the proxy
        loanToken.mint(pos.userProxy, 5e18);

        uint256 aliceBefore = loanToken.balanceOf(alice);

        vm.prank(alice);
        UserProxy(pos.userProxy).recover(address(loanToken));

        assertEq(
            loanToken.balanceOf(alice) - aliceBefore,
            5e18,
            "Alice should recover tokens"
        );
    }

    function test_recover_onlyUser() external {
        uint256 posId = _openCorrelatedPosition(alice, 10e18, 70e16);
        LeveragePosition memory pos = fl.getUserLeveragePosition(alice, posId);

        loanToken.mint(pos.userProxy, 5e18);

        vm.prank(bob);
        vm.expectRevert(FLError.FlashLeverage__Unauthorised.selector);
        UserProxy(pos.userProxy).recover(address(loanToken));
    }
}
