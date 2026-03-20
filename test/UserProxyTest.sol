// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import "./TestBase.sol";
import {UserProxy} from "src/core/FlashLeverage/UserProxy.sol";
import {FLError} from "src/core/libraries/Error.sol";

/// @title UserProxyTest
/// @notice Tests for UserProxy contract: initialization, execute, manual mode, recover
contract UserProxyTest is TestBase {
    uint256 constant INITIAL_COLLATERAL = 10e18;
    uint256 constant STANDARD_LTV = 70e16; // 70%

    // ═══════════════════════════════════════════════
    //              INITIALIZATION
    // ═══════════════════════════════════════════════

    function test_implementation_isInitialized() external view {
        address impl = fl.i_userProxyImplementation();
        UserProxy proxy = UserProxy(impl);

        assertEq(
            proxy.s_user(),
            address(fl),
            "Implementation user should be FL address"
        );
        assertEq(proxy.i_flashLeverage(), address(fl));
        assertEq(proxy.i_morpho(), address(morpho));
    }

    function test_clone_initializesCorrectly() external {
        uint256 posId = _openCorrelatedPosition(
            alice,
            INITIAL_COLLATERAL,
            STANDARD_LTV
        );
        LeveragePosition memory pos = fl.getUserLeveragePosition(alice, posId);

        UserProxy proxy = UserProxy(pos.userProxy);
        assertEq(proxy.s_user(), alice, "Clone user should be alice");
        assertEq(proxy.i_flashLeverage(), address(fl), "Clone FL should match");
        assertEq(
            proxy.i_morpho(),
            address(morpho),
            "Clone morpho should match"
        );
        assertFalse(
            proxy.s_manualMode(),
            "Manual mode should be off by default"
        );
    }

    function test_clone_cannotReinitialize() external {
        uint256 posId = _openCorrelatedPosition(
            alice,
            INITIAL_COLLATERAL,
            STANDARD_LTV
        );
        LeveragePosition memory pos = fl.getUserLeveragePosition(alice, posId);

        vm.expectRevert(
            FLError.FlashLeverage__ProxyAlreadyInitialized.selector
        );
        UserProxy(pos.userProxy).initialize(bob);
    }

    function test_clone_independentState() external {
        _openCorrelatedPosition(alice, INITIAL_COLLATERAL, STANDARD_LTV);
        _openCorrelatedPosition(bob, INITIAL_COLLATERAL, 60e16);

        LeveragePosition memory alicePos = fl.getUserLeveragePosition(alice, 0);
        LeveragePosition memory bobPos = fl.getUserLeveragePosition(bob, 0);

        UserProxy aliceProxy = UserProxy(alicePos.userProxy);
        UserProxy bobProxy = UserProxy(bobPos.userProxy);

        // Different users
        assertEq(aliceProxy.s_user(), alice);
        assertEq(bobProxy.s_user(), bob);

        // Enable manual mode on alice's proxy only
        fl.enableManualMode(alicePos.userProxy);

        assertTrue(aliceProxy.s_manualMode(), "Alice proxy should be manual");
        assertFalse(
            bobProxy.s_manualMode(),
            "Bob proxy should not be affected"
        );
    }

    // ═══════════════════════════════════════════════
    //              EXECUTE
    // ═══════════════════════════════════════════════

    function test_execute_revertsForUnauthorized() external {
        uint256 posId = _openCorrelatedPosition(
            alice,
            INITIAL_COLLATERAL,
            STANDARD_LTV
        );
        LeveragePosition memory pos = fl.getUserLeveragePosition(alice, posId);

        vm.prank(bob);
        vm.expectRevert(FLError.FlashLeverage__Unauthorised.selector);
        UserProxy(pos.userProxy).execute(hex"");
    }

    function test_execute_userBlockedWithoutManualMode() external {
        uint256 posId = _openCorrelatedPosition(
            alice,
            INITIAL_COLLATERAL,
            STANDARD_LTV
        );
        LeveragePosition memory pos = fl.getUserLeveragePosition(alice, posId);

        vm.prank(alice);
        vm.expectRevert(FLError.FlashLeverage__NotInManualMode.selector);
        UserProxy(pos.userProxy).execute(hex"");
    }

    function test_execute_onlyCallsMorpho() external {
        uint256 posId = _openCorrelatedPosition(
            alice,
            INITIAL_COLLATERAL,
            STANDARD_LTV
        );
        LeveragePosition memory pos = fl.getUserLeveragePosition(alice, posId);

        // Enable manual mode so user can call execute
        fl.enableManualMode(pos.userProxy);

        // execute() always calls i_morpho — even with garbage data, the call goes to morpho
        // If morpho doesn't recognize the selector, it reverts — proving target is morpho
        vm.prank(alice);
        vm.expectRevert(FLError.FlashLeverage__ProxyCallFailed.selector);
        UserProxy(pos.userProxy).execute(
            abi.encodeWithSignature("nonExistentFunction()")
        );
    }

    // ═══════════════════════════════════════════════
    //              MANUAL MODE
    // ═══════════════════════════════════════════════

    function test_manualMode_enabledByFlashLeverage() external {
        uint256 posId = _openCorrelatedPosition(
            alice,
            INITIAL_COLLATERAL,
            STANDARD_LTV
        );
        LeveragePosition memory pos = fl.getUserLeveragePosition(alice, posId);

        fl.enableManualMode(pos.userProxy);
        assertTrue(UserProxy(pos.userProxy).s_manualMode());
    }

    function test_manualMode_blocksFlashLeverage() external {
        uint256 posId = _openCorrelatedPosition(
            alice,
            INITIAL_COLLATERAL,
            STANDARD_LTV
        );
        LeveragePosition memory pos = fl.getUserLeveragePosition(alice, posId);

        fl.enableManualMode(pos.userProxy);

        // FL operations should be blocked
        vm.prank(alice);
        vm.expectRevert();
        fl.increaseLeverage(
            posId,
            1e18,
            SwapData({extRouter: address(router), extCalldata: ""}),
            0
        );
    }

    function test_manualMode_cannotBeEnabledByUser() external {
        uint256 posId = _openCorrelatedPosition(
            alice,
            INITIAL_COLLATERAL,
            STANDARD_LTV
        );
        LeveragePosition memory pos = fl.getUserLeveragePosition(alice, posId);

        vm.prank(alice);
        vm.expectRevert(FLError.FlashLeverage__Unauthorised.selector);
        UserProxy(pos.userProxy).enableManualMode();
    }

    function test_manualMode_cannotBeEnabledByRandom() external {
        uint256 posId = _openCorrelatedPosition(
            alice,
            INITIAL_COLLATERAL,
            STANDARD_LTV
        );
        LeveragePosition memory pos = fl.getUserLeveragePosition(alice, posId);

        vm.prank(bob);
        vm.expectRevert(FLError.FlashLeverage__Unauthorised.selector);
        UserProxy(pos.userProxy).enableManualMode();
    }

    function test_manualMode_isIrreversible() external {
        uint256 posId = _openCorrelatedPosition(
            alice,
            INITIAL_COLLATERAL,
            STANDARD_LTV
        );
        LeveragePosition memory pos = fl.getUserLeveragePosition(alice, posId);

        fl.enableManualMode(pos.userProxy);
        assertTrue(UserProxy(pos.userProxy).s_manualMode());

        // No function to disable manual mode — calling enableManualMode again just stays true
        fl.enableManualMode(pos.userProxy);
        assertTrue(
            UserProxy(pos.userProxy).s_manualMode(),
            "Manual mode should remain true"
        );
    }

    // ═══════════════════════════════════════════════
    //              RECOVER
    // ═══════════════════════════════════════════════

    function test_recover_sendsToUser() external {
        uint256 posId = _openCorrelatedPosition(
            alice,
            INITIAL_COLLATERAL,
            STANDARD_LTV
        );
        LeveragePosition memory pos = fl.getUserLeveragePosition(alice, posId);

        uint256 stuckAmount = 5e18;
        loanToken.mint(pos.userProxy, stuckAmount);

        uint256 aliceBefore = loanToken.balanceOf(alice);

        vm.prank(alice);
        UserProxy(pos.userProxy).recover(address(loanToken));

        assertEq(
            loanToken.balanceOf(alice),
            aliceBefore + stuckAmount,
            "Should send to user"
        );
        assertEq(
            loanToken.balanceOf(pos.userProxy),
            0,
            "Proxy should be empty"
        );
    }

    function test_recover_multipleTokens() external {
        uint256 posId = _openCorrelatedPosition(
            alice,
            INITIAL_COLLATERAL,
            STANDARD_LTV
        );
        LeveragePosition memory pos = fl.getUserLeveragePosition(alice, posId);

        // Stuck both token types
        loanToken.mint(pos.userProxy, 5e18);
        collateralToken.mint(pos.userProxy, 3e18);

        uint256 aliceLoanBefore = loanToken.balanceOf(alice);
        uint256 aliceColBefore = collateralToken.balanceOf(alice);

        vm.startPrank(alice);
        UserProxy(pos.userProxy).recover(address(loanToken));
        UserProxy(pos.userProxy).recover(address(collateralToken));
        vm.stopPrank();

        assertEq(loanToken.balanceOf(alice), aliceLoanBefore + 5e18);
        assertEq(collateralToken.balanceOf(alice), aliceColBefore + 3e18);
    }

    function test_recover_zeroBalance_noRevert() external {
        uint256 posId = _openCorrelatedPosition(
            alice,
            INITIAL_COLLATERAL,
            STANDARD_LTV
        );
        LeveragePosition memory pos = fl.getUserLeveragePosition(alice, posId);

        // Should not revert with zero balance
        vm.prank(alice);
        UserProxy(pos.userProxy).recover(address(loanToken));
    }

    function test_recover_revertsOnNonUser() external {
        uint256 posId = _openCorrelatedPosition(
            alice,
            INITIAL_COLLATERAL,
            STANDARD_LTV
        );
        LeveragePosition memory pos = fl.getUserLeveragePosition(alice, posId);

        loanToken.mint(pos.userProxy, 5e18);

        vm.prank(bob);
        vm.expectRevert(FLError.FlashLeverage__Unauthorised.selector);
        UserProxy(pos.userProxy).recover(address(loanToken));
    }
}
