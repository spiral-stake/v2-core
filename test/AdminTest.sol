// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import "./TestBase.sol";
import {FLError} from "src/core/libraries/Error.sol";
import {UserProxy} from "src/core/FlashLeverage/UserProxy.sol";

/// @title AdminTest
/// @notice Tests for owner-only functions: pause, fees, market management, operators, recovery
contract AdminTest is TestBase {
    // ═══════════════════════════════════════════════
    //                 PAUSE / UNPAUSE
    // ═══════════════════════════════════════════════

    function test_pause_blocksLeverage() external {
        fl.pause();

        collateralToken.mint(alice, 10e18);
        vm.startPrank(alice);
        collateralToken.approve(address(fl), 10e18);

        vm.expectRevert(); // EnforcedPause
        fl.leverage(
            alice,
            LeverageParams({
                marketId: correlatedMarketId,
                amountCollateral: 10e18,
                amountFlashLoan: 5e18,
                swapData: SwapData({extRouter: address(router), extCalldata: ""}),
                minTokenOut: 0
            })
        );
        vm.stopPrank();
    }

    function test_pause_blocksDeleverage() external {
        uint256 posId = _openCorrelatedPosition(alice, 10e18, 70e16);
        fl.pause();

        vm.prank(alice);
        vm.expectRevert(); // EnforcedPause
        fl.deleverage(posId, SwapData({extRouter: address(router), extCalldata: ""}), 0);
    }

    function test_pause_blocksSupplyCollateral() external {
        _openCorrelatedPosition(alice, 10e18, 70e16);
        fl.pause();

        collateralToken.mint(alice, 5e18);
        vm.startPrank(alice);
        collateralToken.approve(address(fl), 5e18);
        vm.expectRevert(); // EnforcedPause
        fl.supplyCollateral(alice, 0, 5e18);
        vm.stopPrank();
    }

    function test_pause_blocksRepay() external {
        _openCorrelatedPosition(alice, 10e18, 70e16);
        fl.pause();

        loanToken.mint(alice, 1e18);
        vm.startPrank(alice);
        loanToken.approve(address(fl), 1e18);
        vm.expectRevert(); // EnforcedPause
        fl.repay(alice, 0, 1e18, 0);
        vm.stopPrank();
    }

    function test_pause_blocksWithdrawCollateral() external {
        _openCorrelatedPosition(alice, 10e18, 70e16);
        fl.pause();

        vm.prank(alice);
        vm.expectRevert(); // EnforcedPause
        fl.withdrawCollateral(0, 1e18);
    }

    function test_unpause_resumesOperations() external {
        fl.pause();
        fl.unpause();

        // Should succeed after unpause
        _openCorrelatedPosition(alice, 10e18, 70e16);
        assertEq(fl.getUserLeveragePositions(alice).length, 1);
    }

    function test_pause_onlyOwner() external {
        vm.prank(alice);
        vm.expectRevert();
        fl.pause();
    }

    function test_unpause_onlyOwner() external {
        fl.pause();

        vm.prank(alice);
        vm.expectRevert();
        fl.unpause();
    }

    // ═══════════════════════════════════════════════
    //               MARKET MANAGEMENT
    // ═══════════════════════════════════════════════

    function test_setMarketEnabled_disablesMarket() external {
        fl.setMarketEnabled(correlatedMarketId, false);
        assertFalse(fl.isSupportedMarket(correlatedMarketId));
    }

    function test_setMarketEnabled_reEnablesMarket() external {
        fl.setMarketEnabled(correlatedMarketId, false);
        fl.setMarketEnabled(correlatedMarketId, true);
        assertTrue(fl.isSupportedMarket(correlatedMarketId));
    }

    function test_setMarketEnabled_onlyOwner() external {
        vm.prank(alice);
        vm.expectRevert();
        fl.setMarketEnabled(correlatedMarketId, false);
    }

    function test_setMarketEnabled_revertsOnUnknownMarket() external {
        vm.expectRevert(FLError.FlashLeverage__UnsupportedMarket.selector);
        fl.setMarketEnabled(keccak256("unknown"), false);
    }

    // ═══════════════════════════════════════════════
    //                  FEE UPDATES
    // ═══════════════════════════════════════════════

    function test_updateYieldFee_success() external {
        fl.updateYieldFee(5e16); // 5%
        assertEq(fl.s_yieldFee(), 5e16);
    }

    function test_updateYieldFee_revertsOnZero() external {
        vm.expectRevert(FLError.FlashLeverage__InvalidYieldFee.selector);
        fl.updateYieldFee(0);
    }

    function test_updateYieldFee_revertsAboveMax() external {
        vm.expectRevert(FLError.FlashLeverage__InvalidYieldFee.selector);
        fl.updateYieldFee(11e16); // 11% > MAX_YIELD_FEE (10%)
    }

    function test_updateYieldFee_onlyOwner() external {
        vm.prank(alice);
        vm.expectRevert();
        fl.updateYieldFee(5e16);
    }

    function test_updateDepositFee_success() external {
        fl.updateDepositFee(5e15); // 0.5%
        assertEq(fl.s_depositFee(), 5e15);
    }

    function test_updateDepositFee_canBeZero() external {
        fl.updateDepositFee(0);
        assertEq(fl.s_depositFee(), 0);
    }

    function test_updateDepositFee_revertsAboveMax() external {
        vm.expectRevert(FLError.FlashLeverage__InvalidDepositFee.selector);
        fl.updateDepositFee(2e16); // 2% > MAX_DEPOSIT_FEE (1%)
    }

    // ═══════════════════════════════════════════════
    //               TREASURY UPDATE
    // ═══════════════════════════════════════════════

    function test_updateTreasury_success() external {
        address newTreasury = makeAddr("newTreasury");
        fl.updateTreasury(newTreasury);
        assertEq(fl.s_treasury(), newTreasury);
    }

    function test_updateTreasury_revertsOnZeroAddress() external {
        vm.expectRevert(FLError.FlashLeverage__CannotBeZeroAddress.selector);
        fl.updateTreasury(address(0));
    }

    function test_updateTreasury_onlyOwner() external {
        vm.prank(alice);
        vm.expectRevert();
        fl.updateTreasury(makeAddr("newTreasury"));
    }

    // ═══════════════════════════════════════════════
    //             OPERATOR MANAGEMENT
    // ═══════════════════════════════════════════════

    function test_setApprovedOperator_approve() external {
        fl.setApprovedOperator(bob, true);
        assertTrue(fl.s_approvedOperators(bob));
    }

    function test_setApprovedOperator_revoke() external {
        fl.setApprovedOperator(bob, true);
        fl.setApprovedOperator(bob, false);
        assertFalse(fl.s_approvedOperators(bob));
    }

    function test_setApprovedOperator_revertsOnZeroAddress() external {
        vm.expectRevert(FLError.FlashLeverage__CannotBeZeroAddress.selector);
        fl.setApprovedOperator(address(0), true);
    }

    function test_setApprovedOperator_onlyOwner() external {
        vm.prank(alice);
        vm.expectRevert();
        fl.setApprovedOperator(bob, true);
    }

    // ═══════════════════════════════════════════════
    //              SWAP ROUTER MANAGEMENT
    // ═══════════════════════════════════════════════

    function test_setSwapRouter_whitelist() external {
        address newRouter = makeAddr("newRouter");
        fl.setSwapRouter(newRouter, true);
        assertTrue(fl.isValidSwapRouter(newRouter));
    }

    function test_setSwapRouter_delist() external {
        address newRouter = makeAddr("newRouter");
        fl.setSwapRouter(newRouter, true);
        fl.setSwapRouter(newRouter, false);
        assertFalse(fl.isValidSwapRouter(newRouter));
    }

    function test_setSwapRouter_revertsOnZeroAddress() external {
        vm.expectRevert(FLError.FlashLeverage__CannotBeZeroAddress.selector);
        fl.setSwapRouter(address(0), true);
    }

    function test_setSwapRouter_revertsOnUserProxy() external {
        // Create a position to get a UserProxy
        uint256 posId = _openCorrelatedPosition(alice, 10e18, 70e16);
        LeveragePosition memory pos = fl.getUserLeveragePosition(alice, posId);

        vm.expectRevert(FLError.FlashLeverage__CannotBeUserProxy.selector);
        fl.setSwapRouter(pos.userProxy, true);
    }

    // ═══════════════════════════════════════════════
    //              MANUAL MODE
    // ═══════════════════════════════════════════════

    function test_enableManualMode_success() external {
        uint256 posId = _openCorrelatedPosition(alice, 10e18, 70e16);
        LeveragePosition memory pos = fl.getUserLeveragePosition(alice, posId);

        fl.enableManualMode(pos.userProxy);
        assertTrue(UserProxy(pos.userProxy).s_manualMode());
    }

    function test_enableManualMode_blocksFlashLeverage() external {
        uint256 posId = _openCorrelatedPosition(alice, 10e18, 70e16);
        LeveragePosition memory pos = fl.getUserLeveragePosition(alice, posId);

        fl.enableManualMode(pos.userProxy);

        // FlashLeverage should be blocked from using this proxy
        // (increaseLeverage would call execute on the proxy)
        SwapData memory swap = SwapData({extRouter: address(router), extCalldata: ""});
        vm.prank(alice);
        vm.expectRevert(); // ManualModeEnabled
        fl.increaseLeverage(posId, 1e18, swap, 0);
    }

    function test_enableManualMode_onlyOwner() external {
        uint256 posId = _openCorrelatedPosition(alice, 10e18, 70e16);
        LeveragePosition memory pos = fl.getUserLeveragePosition(alice, posId);

        vm.prank(alice);
        vm.expectRevert();
        fl.enableManualMode(pos.userProxy);
    }

    // ═══════════════════════════════════════════════
    //              RECOVER
    // ═══════════════════════════════════════════════

    function test_recover_sweepsStuckTokens() external {
        // Send some tokens directly to FlashLeverage
        loanToken.mint(address(fl), 100e18);

        uint256 ownerBefore = loanToken.balanceOf(address(this));
        fl.recover(address(loanToken));
        uint256 ownerAfter = loanToken.balanceOf(address(this));

        assertEq(ownerAfter - ownerBefore, 100e18, "Should recover all stuck tokens");
    }

    function test_recover_onlyOwner() external {
        loanToken.mint(address(fl), 100e18);

        vm.prank(alice);
        vm.expectRevert();
        fl.recover(address(loanToken));
    }

    // ═══════════════════════════════════════════════
    //            RENOUNCE OWNERSHIP
    // ═══════════════════════════════════════════════

    function test_renounceOwnership_reverts() external {
        vm.expectRevert(FLError.FlashLeverage__OwnershipRenunciationDisabled.selector);
        fl.renounceOwnership();
    }
}
