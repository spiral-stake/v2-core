// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

// ─── How to run ───────────────────────────────────────────────────────────────
//   halmos --match-contract SymUserProxy --forge-build-out abi --solver-timeout-assertion 60000
//
// UserProxy is the isolated wallet that holds every user's Morpho position.
// Any unauthorized caller reaching execute(), initialize(), or recover()
// could drain the entire position. These proofs show that is impossible for
// ALL possible caller addresses — not just sampled ones.
//
// NOTE: Uses native Solidity assert() and try/catch instead of Foundry
//       assertion cheat codes for Halmos 0.1.x compatibility.
// ─────────────────────────────────────────────────────────────────────────────

import {Test} from "forge-std/Test.sol";
import {UserProxy} from "src/core/FlashLeverage/UserProxy.sol";
import {FLError} from "src/core/libraries/Error.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";

contract SymUserProxy is Test {

    UserProxy proxy;
    address constant FL      = address(0xF1a5F1a5);
    address constant MORPHO  = address(0xB0B0B0B0);
    address constant USER    = address(0xA11CE);

    function setUp() public {
        proxy = new UserProxy(FL, MORPHO);
        vm.prank(FL);
        proxy.initialize(USER);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // initialize
    // ═══════════════════════════════════════════════════════════════════════

    /// PROPERTY: For a fresh (uninitialized) proxy, any caller that is NOT
    ///           FlashLeverage is rejected with Unauthorised.
    /// WHY: initialize sets s_user — the address that can withdraw collateral.
    ///      An attacker who calls initialize first would steal all future
    ///      collateral deposited by the real user.
    function check_initialize_onlyFlashLeverageMayCall(
        address caller,
        address victim
    ) external {
        UserProxy fresh = new UserProxy(FL, MORPHO);
        vm.assume(caller != FL);
        vm.prank(caller);
        bool reverted;
        try fresh.initialize(victim) {
            reverted = false;
        } catch {
            reverted = true;
        }
        assert(reverted);
    }

    /// PROPERTY: initialize cannot be called a second time, regardless of caller.
    /// WHY: Re-initialization would let an attacker hijack the proxy owner
    ///      (s_user) of an existing live position. The clone is one-time-use.
    function check_initialize_cannotCallTwice(address secondCaller, address newUser) external {
        // proxy is already initialized with USER in setUp
        vm.prank(secondCaller); // even FL itself must fail on re-init
        bool reverted;
        try proxy.initialize(newUser) {
            reverted = false;
        } catch {
            reverted = true;
        }
        assert(reverted);
    }

    /// PROPERTY: After a valid initialize, s_user equals exactly the address passed.
    /// WHY: Proves no address aliasing or truncation happens during initialization.
    ///      A mismatch would mean the wrong address controls the proxy.
    function check_initialize_storesUserExactly(address initUser) external {
        vm.assume(initUser != address(0));
        UserProxy fresh = new UserProxy(FL, MORPHO);
        vm.prank(FL);
        fresh.initialize(initUser);
        assert(fresh.s_user() == initUser);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // execute
    // ═══════════════════════════════════════════════════════════════════════

    /// PROPERTY: Any caller that is neither FL nor s_user is rejected with
    ///           Unauthorised — regardless of the calldata passed.
    /// WHY: execute() is the gateway to all Morpho operations (supply, borrow,
    ///      withdrawCollateral). Unauthorized access is equivalent to arbitrary
    ///      fund manipulation on Morpho on behalf of the user.
    function check_execute_thirdPartyAlwaysReverts(
        address caller,
        bytes calldata data
    ) external {
        vm.assume(caller != FL);
        vm.assume(caller != USER);
        vm.prank(caller);
        bool reverted;
        try proxy.execute(data) {
            reverted = false;
        } catch {
            reverted = true;
        }
        assert(reverted);
    }

    /// PROPERTY: When manual mode is OFF (default), the user (s_user) cannot
    ///           call execute — only FL may.
    /// WHY: Prevents users from bypassing FlashLeverage's LTV and fee checks
    ///      by calling Morpho directly through the proxy.
    function check_execute_userRevertsWhenManualModeOff() external {
        assert(!proxy.s_manualMode());
        vm.prank(USER);
        bool reverted;
        try proxy.execute(hex"") {
            reverted = false;
        } catch {
            reverted = true;
        }
        assert(reverted);
    }

    /// PROPERTY: When manual mode is ON, FlashLeverage cannot call execute.
    /// WHY: Manual mode is a mutual-exclusion flag — either FL controls the
    ///      proxy (normal) or the user does (recovery). Both being active
    ///      simultaneously would create a race condition over Morpho state.
    function check_execute_flRevertsWhenManualModeOn() external {
        vm.prank(FL);
        proxy.enableManualMode();
        assert(proxy.s_manualMode());

        vm.prank(FL);
        bool reverted;
        try proxy.execute(hex"") {
            reverted = false;
        } catch {
            reverted = true;
        }
        assert(reverted);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // enableManualMode
    // ═══════════════════════════════════════════════════════════════════════

    /// PROPERTY: Any caller that is NOT FlashLeverage cannot enable manual mode.
    /// WHY: enableManualMode gates the user's ability to call execute directly.
    ///      An attacker who enables it first could lock FL out of the proxy
    ///      (DoS) and then manipulate the position themselves.
    function check_enableManualMode_onlyFlashLeverage(address caller) external {
        vm.assume(caller != FL);
        vm.prank(caller);
        bool reverted;
        try proxy.enableManualMode() {
            reverted = false;
        } catch {
            reverted = true;
        }
        assert(reverted);
    }

    /// PROPERTY: Once enabled, manual mode is irreversible (monotone flag).
    /// WHY: This is an emergency mechanism. If it could be toggled off,
    ///      FL could regain control after the user entered manual mode,
    ///      invalidating the user's assumption of exclusive control.
    function check_enableManualMode_isIrreversible() external {
        vm.prank(FL);
        proxy.enableManualMode();
        assert(proxy.s_manualMode());

        // Calling again does not revert but mode stays true
        vm.prank(FL);
        proxy.enableManualMode();
        assert(proxy.s_manualMode());
    }

    // ═══════════════════════════════════════════════════════════════════════
    // recover
    // ═══════════════════════════════════════════════════════════════════════

    /// PROPERTY: Any caller that is NOT s_user is rejected.
    /// WHY: recover() sweeps all tokens to s_user. If any other address could
    ///      call it, reward tokens or accidentally sent funds would be stolen.
    function check_recover_onlyUserMayCall(address caller) external {
        MockERC20 token = new MockERC20("T", "T", 18);
        token.mint(address(proxy), 1e18);

        vm.assume(caller != USER);
        vm.prank(caller);
        bool reverted;
        try proxy.recover(address(token)) {
            reverted = false;
        } catch {
            reverted = true;
        }
        assert(reverted);
    }

    /// PROPERTY: recover() sends the entire proxy balance to s_user (not partial).
    /// WHY: Any residual tokens left in the proxy after recovery would be
    ///      inaccessible to the user — effectively a permanent fund lock.
    function check_recover_sendsFullBalanceToUser(uint256 dustAmount) external {
        vm.assume(dustAmount > 0 && dustAmount <= 1_000e18);
        MockERC20 token = new MockERC20("T", "T", 18);
        token.mint(address(proxy), dustAmount);

        uint256 userBefore = token.balanceOf(USER);
        vm.prank(USER);
        proxy.recover(address(token));

        assert(token.balanceOf(address(proxy)) == 0);
        assert(token.balanceOf(USER) == userBefore + dustAmount);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // Immutable integrity
    // ═══════════════════════════════════════════════════════════════════════

    /// PROPERTY: i_flashLeverage and i_morpho are set to constructor values
    ///           and can NEVER change.
    /// WHY: If an attacker could change i_flashLeverage, they could point the
    ///      proxy at a malicious contract and steal all Morpho positions.
    ///      Immutables in Solidity 0.8 are bytecode-embedded — this proves
    ///      the values are exactly what was passed to the constructor.
    function check_immutables_neverChange(
        address anyFL,
        address anyMorpho
    ) external {
        UserProxy fresh = new UserProxy(anyFL, anyMorpho);
        assert(fresh.i_flashLeverage() == anyFL);
        assert(fresh.i_morpho()        == anyMorpho);
    }
}
