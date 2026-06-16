// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import {FuzzTestBase} from "test/fuzz/FuzzTestBase.sol";
import {FLError} from "src/core/libraries/Error.sol";
import {MarketConfig} from "src/core/structs/MarketConfig.sol";

/// @notice Fuzz tests for FlashLeverage admin functions: fee updates, access control,
///         pause/unpause, operators, markets, swap routers.
contract FuzzAdmin is FuzzTestBase {

    // Private constants mirrored here for range checking
    uint256 constant MAX_YIELD_FEE = 10e16;  // 10%
    uint256 constant MAX_DEPOSIT_FEE = 1e16; // 1%

    // ─── updateYieldFee ────────────────────────────────────────────────────────

    function testFuzz_updateYieldFee_validRange(uint256 fee) external {
        fee = bound(fee, 0, MAX_YIELD_FEE);
        fl.updateYieldFee(fee);
        assertEq(fl.s_yieldFee(), fee);
    }

    function testFuzz_updateYieldFee_zeroIsAllowed() external {
        fl.updateYieldFee(0);
        assertEq(fl.s_yieldFee(), 0);
    }

    function testFuzz_updateYieldFee_tooHighReverts(uint256 fee) external {
        fee = bound(fee, MAX_YIELD_FEE + 1, type(uint256).max);
        vm.expectRevert(FLError.FlashLeverage__InvalidYieldFee.selector);
        fl.updateYieldFee(fee);
    }

    function testFuzz_updateYieldFee_nonOwnerReverts(address caller, uint256 fee) external {
        vm.assume(caller != owner);
        fee = bound(fee, 1, MAX_YIELD_FEE);
        vm.prank(caller);
        vm.expectRevert();
        fl.updateYieldFee(fee);
    }

    // ─── updateDepositFee ──────────────────────────────────────────────────────

    function testFuzz_updateDepositFee_validRange(uint256 fee) external {
        fee = bound(fee, 0, MAX_DEPOSIT_FEE);
        fl.updateDepositFee(fee);
        assertEq(fl.s_depositFee(), fee);
    }

    function testFuzz_updateDepositFee_tooHighReverts(uint256 fee) external {
        fee = bound(fee, MAX_DEPOSIT_FEE + 1, type(uint256).max);
        vm.expectRevert(FLError.FlashLeverage__InvalidDepositFee.selector);
        fl.updateDepositFee(fee);
    }

    function testFuzz_updateDepositFee_nonOwnerReverts(address caller, uint256 fee) external {
        vm.assume(caller != owner);
        fee = bound(fee, 0, MAX_DEPOSIT_FEE);
        vm.prank(caller);
        vm.expectRevert();
        fl.updateDepositFee(fee);
    }

    // ─── updateTreasury ────────────────────────────────────────────────────────

    function testFuzz_updateTreasury_validAddress(address newTreasury) external {
        vm.assume(newTreasury != address(0));
        fl.updateTreasury(newTreasury);
        assertEq(fl.s_treasury(), newTreasury);
    }

    function testFuzz_updateTreasury_zeroAddressReverts() external {
        vm.expectRevert(FLError.FlashLeverage__CannotBeZeroAddress.selector);
        fl.updateTreasury(address(0));
    }

    function testFuzz_updateTreasury_nonOwnerReverts(address caller, address newTreasury) external {
        vm.assume(caller != owner);
        vm.assume(newTreasury != address(0));
        vm.prank(caller);
        vm.expectRevert();
        fl.updateTreasury(newTreasury);
    }

    // ─── setApprovedOperator ───────────────────────────────────────────────────

    function testFuzz_setApprovedOperator_ownerCanSet(address operator, bool value) external {
        vm.assume(operator != address(0));
        fl.setApprovedOperator(operator, value);
        assertEq(fl.s_approvedOperators(operator), value);
    }

    function testFuzz_setApprovedOperator_zeroAddressReverts(bool value) external {
        vm.expectRevert(FLError.FlashLeverage__CannotBeZeroAddress.selector);
        fl.setApprovedOperator(address(0), value);
    }

    function testFuzz_setApprovedOperator_nonOwnerReverts(address caller, address operator) external {
        vm.assume(caller != owner);
        vm.assume(operator != address(0));
        vm.prank(caller);
        vm.expectRevert();
        fl.setApprovedOperator(operator, true);
    }

    // ─── setSwapRouter ─────────────────────────────────────────────────────────

    function testFuzz_setSwapRouter_ownerCanSet(address swapRouter, bool value) external {
        vm.assume(swapRouter != address(0));
        vm.assume(swapRouter != address(morpho)); // avoid CannotBeMorpho revert
        // Skip Ethereum precompiles (0x01–0xFF): their staticcall returns data that can
        // accidentally satisfy _isUserProxy's "i_flashLeverage()" ABI check.
        vm.assume(uint160(swapRouter) > 0xFF);
        // Exclude addresses that look like user proxies of this FlashLeverage instance
        (bool success, bytes memory data) = swapRouter.staticcall(
            abi.encodeWithSignature("i_flashLeverage()")
        );
        bool isProxy = success && data.length >= 32 &&
            abi.decode(data, (address)) == address(fl);
        vm.assume(!isProxy);

        fl.setSwapRouter(swapRouter, value);
        assertEq(fl.isValidSwapRouter(swapRouter), value);
    }

    function testFuzz_setSwapRouter_zeroAddressReverts(bool value) external {
        vm.expectRevert(FLError.FlashLeverage__CannotBeZeroAddress.selector);
        fl.setSwapRouter(address(0), value);
    }

    function testFuzz_setSwapRouter_morphoAddressReverts(bool value) external {
        // Use the `morpho` field from TestBase directly — avoids any
        // call-through that could be confused by test harness state.
        vm.expectRevert(FLError.FlashLeverage__CannotBeMorpho.selector);
        fl.setSwapRouter(address(morpho), value);
    }

    function testFuzz_setSwapRouter_nonOwnerReverts(address caller, address swapRouter) external {
        vm.assume(caller != owner);
        vm.assume(swapRouter != address(0));
        vm.prank(caller);
        vm.expectRevert();
        fl.setSwapRouter(swapRouter, true);
    }

    // ─── setMarketEnabled ──────────────────────────────────────────────────────

    function testFuzz_setMarketEnabled_ownerCanToggle(bool value) external {
        fl.setMarketEnabled(correlatedMarketId, value);
        assertEq(fl.isSupportedMarket(correlatedMarketId), value);
    }

    function testFuzz_setMarketEnabled_unsupportedMarketReverts(bytes32 fakeId) external {
        vm.assume(fakeId != correlatedMarketId && fakeId != nonCorrelatedMarketId);
        vm.expectRevert(FLError.FlashLeverage__UnsupportedMarket.selector);
        fl.setMarketEnabled(fakeId, true);
    }

    function testFuzz_setMarketEnabled_nonOwnerReverts(address caller) external {
        vm.assume(caller != owner);
        vm.prank(caller);
        vm.expectRevert();
        fl.setMarketEnabled(correlatedMarketId, false);
    }

    // ─── pause / unpause ───────────────────────────────────────────────────────

    function testFuzz_pause_ownerCanPause() external {
        fl.pause();
        assertTrue(fl.paused());
    }

    function testFuzz_pause_arbitraryCallerReverts(address caller) external {
        vm.assume(caller != owner);
        vm.prank(caller);
        vm.expectRevert();
        fl.pause();
    }

    function testFuzz_unpause_onlyOwnerSucceeds() external {
        fl.pause();
        fl.unpause();
        assertFalse(fl.paused());
    }

    function testFuzz_unpause_nonOwnerReverts(address caller) external {
        vm.assume(caller != owner);
        fl.pause();
        vm.prank(caller);
        vm.expectRevert();
        fl.unpause();
    }

    // ─── renounceOwnership ────────────────────────────────────────────────────

    function testFuzz_renounceOwnership_alwaysReverts(address caller) external {
        // Even owner calling renounceOwnership reverts
        vm.prank(caller);
        vm.expectRevert(FLError.FlashLeverage__OwnershipRenunciationDisabled.selector);
        fl.renounceOwnership();
    }

    // ─── addSupportedMarkets ───────────────────────────────────────────────────

    function testFuzz_addSupportedMarkets_duplicateReverts() external {
        // The correlated market was already added in setUp — adding again must revert
        MarketConfig[] memory configs = new MarketConfig[](1);
        configs[0] = MarketConfig({marketId: correlatedMarketId, isCorrelated: true});

        vm.expectRevert(FLError.FlashLeverage__MarketAlreadyExists.selector);
        fl.addSupportedMarkets(configs);
    }

    function testFuzz_addSupportedMarkets_nonOwnerReverts(address caller) external {
        vm.assume(caller != owner);
        MarketConfig[] memory configs = new MarketConfig[](0);

        vm.prank(caller);
        vm.expectRevert();
        fl.addSupportedMarkets(configs);
    }
}
