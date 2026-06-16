// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import "./TestBase.sol";
import {UserProxy} from "src/core/FlashLeverage/UserProxy.sol";
import {FLError} from "src/core/libraries/Error.sol";
import {IMorpho, IMorphoBase, MarketParams} from "@morpho/interfaces/IMorpho.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

/// @title ExecuteExternalTest
/// @notice Adversarial audit of UserProxy.executeExternal — the arbitrary external-call
///         function added to let s_user interact with reward distributors etc.
///
///         The UserProxy is the on-chain identity that *owns* each user's Morpho
///         position. The protocol's safety rests on a single property:
///
///             A Morpho position can only be REDUCED (borrow/withdraw) or
///             DELEGATED (setAuthorization) by a call where msg.sender == proxy.
///
///         FlashLeverage produces such calls only through the gated execute().
///         executeExternal must therefore be PROVABLY unable to reach Morpho —
///         directly or by authorizing a third party — or the entire TVL is at risk.
///
///         These tests run against the REAL Morpho contract (see TestBase) so the
///         authorization / position invariants are checked against production logic,
///         not a mock.
contract ExecuteExternalTest is TestBase {
    using Math for uint256;

    uint256 constant INITIAL_COLLATERAL = 10e18;
    uint256 constant STANDARD_LTV = 70e16; // 70%

    UserProxy internal proxy;
    MockERC20 internal rewardToken;

    function setUp() public override {
        super.setUp();
        rewardToken = new MockERC20("Reward", "RWD", 18);
        uint256 posId = _openCorrelatedPosition(
            alice,
            INITIAL_COLLATERAL,
            STANDARD_LTV
        );
        LeveragePosition memory pos = fl.getUserLeveragePosition(alice, posId);
        proxy = UserProxy(pos.userProxy);
    }

    // ═══════════════════════════════════════════════
    //              ACCESS CONTROL
    // ═══════════════════════════════════════════════

    /// Only s_user may call executeExternal. FlashLeverage itself must NOT —
    /// otherwise a bug/compromise in FL accounting could route arbitrary calls.
    function test_executeExternal_revertsForFlashLeverage() external {
        vm.prank(address(fl));
        vm.expectRevert(FLError.FlashLeverage__Unauthorised.selector);
        proxy.executeExternal(address(rewardToken), "");
    }

    function test_executeExternal_revertsForRandomCaller() external {
        vm.prank(bob);
        vm.expectRevert(FLError.FlashLeverage__Unauthorised.selector);
        proxy.executeExternal(address(rewardToken), "");
    }

    function test_executeExternal_revertsForOwner() external {
        // The protocol owner has no business driving a user's proxy
        vm.prank(owner);
        vm.expectRevert(FLError.FlashLeverage__Unauthorised.selector);
        proxy.executeExternal(address(rewardToken), "");
    }

    function testFuzz_executeExternal_onlyUser(address caller) external {
        vm.assume(caller != alice);
        vm.prank(caller);
        vm.expectRevert(FLError.FlashLeverage__Unauthorised.selector);
        proxy.executeExternal(address(rewardToken), "");
    }

    /// Access control holds even after manual mode is enabled (recovery state).
    function test_executeExternal_onlyUser_evenInManualMode() external {
        fl.enableManualMode(address(proxy));
        vm.prank(bob);
        vm.expectRevert(FLError.FlashLeverage__Unauthorised.selector);
        proxy.executeExternal(address(rewardToken), "");
    }

    // ═══════════════════════════════════════════════
    //          MORPHO IS UNREACHABLE (THE LINCHPIN)
    // ═══════════════════════════════════════════════

    /// Direct Morpho target is rejected before any call is made — empty calldata.
    function test_executeExternal_blocksMorpho_emptyData() external {
        vm.prank(alice);
        vm.expectRevert(FLError.FlashLeverage__CannotBeMorpho.selector);
        proxy.executeExternal(address(morpho), "");
    }

    /// The dangerous one: setAuthorization. If this ever succeeded, the user
    /// could authorize an EOA over the proxy and drain the whole position.
    function test_executeExternal_blocksMorpho_setAuthorization() external {
        bytes memory data = abi.encodeCall(
            IMorphoBase.setAuthorization,
            (alice, true)
        );
        vm.prank(alice);
        vm.expectRevert(FLError.FlashLeverage__CannotBeMorpho.selector);
        proxy.executeExternal(address(morpho), data);
    }

    /// withdrawCollateral straight to the attacker — blocked at the target check.
    function test_executeExternal_blocksMorpho_withdrawCollateral() external {
        bytes memory data = abi.encodeWithSignature(
            "withdrawCollateral((address,address,address,address,uint256),uint256,address,address)",
            correlatedMarket,
            INITIAL_COLLATERAL,
            address(proxy),
            alice
        );
        vm.prank(alice);
        vm.expectRevert(FLError.FlashLeverage__CannotBeMorpho.selector);
        proxy.executeExternal(address(morpho), data);
    }

    /// Fuzz arbitrary calldata at Morpho — must ALWAYS revert with CannotBeMorpho,
    /// proving the block is on the target address, never the calldata shape.
    function testFuzz_executeExternal_blocksMorpho_anyData(
        bytes calldata data
    ) external {
        vm.prank(alice);
        vm.expectRevert(FLError.FlashLeverage__CannotBeMorpho.selector);
        proxy.executeExternal(address(morpho), data);
    }

    // ═══════════════════════════════════════════════
    //          FLASHLEVERAGE IS UNREACHABLE
    // ═══════════════════════════════════════════════

    function test_executeExternal_blocksFlashLeverage() external {
        vm.prank(alice);
        vm.expectRevert(FLError.FlashLeverage__Unauthorised.selector);
        proxy.executeExternal(address(fl), "");
    }

    function testFuzz_executeExternal_blocksFlashLeverage_anyData(
        bytes calldata data
    ) external {
        vm.prank(alice);
        vm.expectRevert(FLError.FlashLeverage__Unauthorised.selector);
        proxy.executeExternal(address(fl), data);
    }

    // ═══════════════════════════════════════════════
    //   END-TO-END: POSITION CANNOT BE DRAINED OR DELEGATED
    // ═══════════════════════════════════════════════

    /// The whole point. After the user routes calls through an arbitrary, fully
    /// attacker-controlled contract via executeExternal, the Morpho position must
    /// be byte-for-byte unchanged and no authorization may exist.
    function test_executeExternal_cannotDrainPositionViaHelper() external {
        Position memory before = fl.getMorphoPosition(
            address(proxy),
            correlatedMarket
        );
        assertGt(before.collateral, 0, "precondition: position has collateral");

        MaliciousHelper helper = new MaliciousHelper(
            address(morpho),
            correlatedMarket,
            address(proxy),
            alice
        );

        // Alice (the legitimate user) is fully cooperating with the attacker here.
        // The helper tries every Morpho trick using msg.sender == proxy as leverage.
        vm.prank(alice);
        proxy.executeExternal(
            address(helper),
            abi.encodeCall(MaliciousHelper.tryDrain, ())
        );

        Position memory afterPos = fl.getMorphoPosition(
            address(proxy),
            correlatedMarket
        );
        assertEq(
            afterPos.collateral,
            before.collateral,
            "collateral must be untouched"
        );
        assertEq(
            afterPos.borrowShares,
            before.borrowShares,
            "borrow must be untouched"
        );

        // No third party can have been authorized over the proxy's position.
        assertFalse(
            morpho.isAuthorized(address(proxy), alice),
            "alice must not be authorized over proxy"
        );
        assertFalse(
            morpho.isAuthorized(address(proxy), address(helper)),
            "helper must not be authorized over proxy"
        );
    }

    /// A directly authorized EOA still cannot move the position, because the
    /// authorization can never be granted in the first place. We assert the
    /// negative directly: even with full user cooperation, isAuthorized stays false.
    function test_executeExternal_authorizationNeverGranted() external {
        address[3] memory candidates = [alice, bob, address(this)];

        for (uint256 i; i < candidates.length; ++i) {
            // Attempt via a helper that calls setAuthorization itself (msg.sender = helper)
            AuthGriefer griefer = new AuthGriefer(
                address(morpho),
                candidates[i]
            );
            vm.prank(alice);
            proxy.executeExternal(
                address(griefer),
                abi.encodeCall(AuthGriefer.tryAuthorize, ())
            );

            // The griefer can only authorize over ITS OWN (empty) position, never the proxy's.
            assertFalse(
                morpho.isAuthorized(address(proxy), candidates[i]),
                "no candidate may be authorized over the proxy"
            );
        }
    }

    // ═══════════════════════════════════════════════
    //          SELF-CALL CANNOT ESCALATE
    // ═══════════════════════════════════════════════

    /// target == proxy itself is NOT blocked by the require checks, but every
    /// reentrant entry point is gated on s_user / i_flashLeverage, and the proxy
    /// is neither — so self-calls cannot escalate privileges.

    function test_selfCall_cannotCallExecute() external {
        // proxy.execute requires msg.sender == FL or (user && manualMode).
        // Via executeExternal, the inner msg.sender is the proxy → Unauthorised,
        // which bubbles up as ProxyCallFailed.
        bytes memory inner = abi.encodeCall(UserProxy.execute, (hex""));
        vm.prank(alice);
        vm.expectRevert(FLError.FlashLeverage__ProxyCallFailed.selector);
        proxy.executeExternal(address(proxy), inner);
    }

    function test_selfCall_cannotCallRecover() external {
        bytes memory inner = abi.encodeCall(
            UserProxy.recover,
            (address(rewardToken))
        );
        vm.prank(alice);
        vm.expectRevert(FLError.FlashLeverage__ProxyCallFailed.selector);
        proxy.executeExternal(address(proxy), inner);
    }

    function test_selfCall_cannotEnableManualMode() external {
        bytes memory inner = abi.encodeCall(UserProxy.enableManualMode, ());
        vm.prank(alice);
        vm.expectRevert(FLError.FlashLeverage__ProxyCallFailed.selector);
        proxy.executeExternal(address(proxy), inner);
        assertFalse(proxy.s_manualMode(), "manual mode must stay off");
    }

    function test_selfCall_cannotReinitialize() external {
        bytes memory inner = abi.encodeCall(UserProxy.initialize, (bob));
        vm.prank(alice);
        vm.expectRevert(FLError.FlashLeverage__ProxyCallFailed.selector);
        proxy.executeExternal(address(proxy), inner);
        assertEq(proxy.s_user(), alice, "owner must stay alice");
    }

    function test_selfCall_cannotNestExecuteExternal() external {
        bytes memory inner = abi.encodeCall(
            UserProxy.executeExternal,
            (address(rewardToken), "")
        );
        vm.prank(alice);
        vm.expectRevert(FLError.FlashLeverage__ProxyCallFailed.selector);
        proxy.executeExternal(address(proxy), inner);
    }

    // ═══════════════════════════════════════════════
    //          REENTRANCY INTO FLASHLEVERAGE
    // ═══════════════════════════════════════════════

    /// A malicious target reentering FlashLeverage acts as ITSELF (msg.sender =
    /// helper), so it has no positions and cannot touch alice's. Reentrancy buys
    /// nothing; we assert alice's position is untouched.
    function test_executeExternal_reentryIntoFlGainsNothing() external {
        Position memory before = fl.getMorphoPosition(
            address(proxy),
            correlatedMarket
        );

        FlReentrant attacker = new FlReentrant(address(fl));
        vm.prank(alice);
        // The reentrant call to fl.deleverage(0,...) reverts inside the helper
        // (helper has no position 0); helper swallows it so executeExternal succeeds.
        proxy.executeExternal(
            address(attacker),
            abi.encodeCall(FlReentrant.tryReenter, ())
        );

        Position memory afterPos = fl.getMorphoPosition(
            address(proxy),
            correlatedMarket
        );
        assertEq(afterPos.collateral, before.collateral);
        assertEq(afterPos.borrowShares, before.borrowShares);
    }

    // ═══════════════════════════════════════════════
    //          CROSS-USER ISOLATION
    // ═══════════════════════════════════════════════

    /// Alice cannot use her executeExternal to reach into Bob's proxy.
    function test_executeExternal_cannotTouchAnotherUsersProxy() external {
        uint256 bobPos = _openCorrelatedPosition(
            bob,
            INITIAL_COLLATERAL,
            STANDARD_LTV
        );
        address bobProxy = fl.getUserLeveragePosition(bob, bobPos).userProxy;

        // Alice routes a call at bob's proxy. Inner msg.sender = alice's proxy,
        // which is neither bob nor FL → every bob-proxy entry point reverts.
        bytes memory inner = abi.encodeCall(
            UserProxy.recover,
            (address(rewardToken))
        );
        vm.prank(alice);
        vm.expectRevert(FLError.FlashLeverage__ProxyCallFailed.selector);
        proxy.executeExternal(bobProxy, inner);
    }

    // ═══════════════════════════════════════════════
    //          POSITIVE PATH + ERROR BUBBLING
    // ═══════════════════════════════════════════════

    /// The intended use case: claim rewards from an external distributor.
    function test_executeExternal_claimRewards_success() external {
        RewardDistributor dist = new RewardDistributor(address(rewardToken));
        rewardToken.mint(address(dist), 100e18);

        vm.prank(alice);
        bytes memory ret = proxy.executeExternal(
            address(dist),
            abi.encodeCall(RewardDistributor.claim, (address(proxy), 100e18))
        );

        assertEq(
            rewardToken.balanceOf(address(proxy)),
            100e18,
            "rewards delivered to proxy"
        );
        // Return data bubbles back to the caller.
        assertEq(abi.decode(ret, (bool)), true, "claim returns true");

        // And the user can sweep them out as before.
        vm.prank(alice);
        proxy.recover(address(rewardToken));
        assertEq(rewardToken.balanceOf(alice), 100e18, "swept to alice");
    }

    /// A reverting external call must surface as ProxyCallFailed, not silently pass.
    function test_executeExternal_bubblesFailure() external {
        Reverter r = new Reverter();
        vm.prank(alice);
        vm.expectRevert(FLError.FlashLeverage__ProxyCallFailed.selector);
        proxy.executeExternal(address(r), abi.encodeCall(Reverter.boom, ()));
    }

    /// Calling an EOA / address with no code: low-level call to a codeless
    /// address returns success=true with empty data, so it does not revert.
    /// This is acceptable (no state can change) but pinned here as documented behavior.
    function test_executeExternal_callToEOA_returnsEmpty() external {
        vm.prank(alice);
        bytes memory ret = proxy.executeExternal(makeAddr("randomEOA"), "");
        assertEq(ret.length, 0);
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Attack / helper contracts
// ─────────────────────────────────────────────────────────────────────────────

/// Tries to extract the proxy's Morpho collateral using the fact that it is
/// called WITH msg.sender == proxy upstream. But when IT calls Morpho, Morpho
/// sees msg.sender == helper, not proxy, so every reduction reverts.
contract MaliciousHelper {
    IMorpho immutable morpho;
    MarketParams market;
    address immutable victimProxy;
    address immutable attacker;

    constructor(
        address _morpho,
        MarketParams memory _market,
        address _victimProxy,
        address _attacker
    ) {
        morpho = IMorpho(_morpho);
        market = _market;
        victimProxy = _victimProxy;
        attacker = _attacker;
    }

    function tryDrain() external {
        // 1) Try to authorize the attacker over the proxy — sets auth for THIS
        //    contract's position, not the proxy's. Harmless.
        try morpho.setAuthorization(attacker, true) {} catch {}

        // 2) Try to withdraw the proxy's collateral to the attacker. Reverts
        //    (helper is not authorized over victimProxy). Swallow so the outer
        //    executeExternal still succeeds and we can assert state is intact.
        try
            morpho.withdrawCollateral(market, type(uint128).max, victimProxy, attacker)
        {} catch {}

        // 3) Try to borrow against the proxy to the attacker. Also reverts.
        try
            morpho.borrow(market, 1, 0, victimProxy, attacker)
        {} catch {}
    }
}

/// Calls setAuthorization itself; can only ever authorize over its own position.
contract AuthGriefer {
    IMorpho immutable morpho;
    address immutable who;

    constructor(address _morpho, address _who) {
        morpho = IMorpho(_morpho);
        who = _who;
    }

    function tryAuthorize() external {
        morpho.setAuthorization(who, true);
    }
}

/// Reenters FlashLeverage from within an executeExternal call.
contract FlReentrant {
    address immutable fl;

    constructor(address _fl) {
        fl = _fl;
    }

    function tryReenter() external {
        // deleverage(positionId=0, ...) — this contract has no positions, so it
        // reverts on the storage lookup. Swallowed to prove "no effect", not "no call".
        (bool ok, ) = fl.call(
            abi.encodeWithSignature(
                "deleverage(uint256,uint256,(address,bytes),uint256)",
                uint256(0),
                uint256(0),
                bytes(""),
                uint256(0)
            )
        );
        ok; // ignore
    }
}

/// Minimal reward distributor for the positive-path test.
contract RewardDistributor {
    address immutable token;

    constructor(address _token) {
        token = _token;
    }

    function claim(address to, uint256 amount) external returns (bool) {
        (bool ok, ) = token.call(
            abi.encodeWithSignature("transfer(address,uint256)", to, amount)
        );
        require(ok, "transfer failed");
        return true;
    }
}

contract Reverter {
    function boom() external pure {
        revert("boom");
    }
}
