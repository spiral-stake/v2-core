// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import "./TestBase.sol";
import {UserProxy} from "src/core/FlashLeverage/UserProxy.sol";
import {FLError} from "src/core/libraries/Error.sol";

/// @title AdminTest
/// @notice Tests for owner-only functions: pause, fees, market management, operators, recovery
contract AdminTest is TestBase {
    using Math for uint256;

    uint256 constant INITIAL_COLLATERAL = 10e18;
    uint256 constant STANDARD_LTV = 70e16; // 70%

    // ═══════════════════════════════════════════════
    //                 PAUSE / UNPAUSE
    // ═══════════════════════════════════════════════

    function test_pause_blocksLeverage() external {
        fl.pause();

        vm.prank(alice);
        vm.expectRevert();
        fl.leverage(alice, _dummyLeverageParams());
    }

    function test_pause_blocksDeleverage() external {
        uint256 posId = _openCorrelatedPosition(
            alice,
            INITIAL_COLLATERAL,
            STANDARD_LTV
        );
        fl.pause();

        vm.prank(alice);
        vm.expectRevert();
        fl.deleverage(posId, 0, _emptySwap(), 0);
    }

    function test_pause_blocksIncreaseLeverage() external {
        uint256 posId = _openCorrelatedPosition(
            alice,
            INITIAL_COLLATERAL,
            50e16
        );
        fl.pause();

        vm.prank(alice);
        vm.expectRevert();
        fl.increaseLeverage(posId, 1e18, _emptySwap(), 0);
    }

    function test_pause_blocksSupplyCollateral() external {
        _openCorrelatedPosition(alice, INITIAL_COLLATERAL, STANDARD_LTV);
        fl.pause();

        collateralToken.mint(alice, 5e18);
        vm.startPrank(alice);
        collateralToken.approve(address(fl), 5e18);
        vm.expectRevert();
        fl.supplyCollateral(alice, 0, 5e18);
        vm.stopPrank();
    }

    function test_pause_blocksBorrow() external {
        uint256 posId = _openCorrelatedPosition(
            alice,
            INITIAL_COLLATERAL,
            50e16
        );
        fl.pause();

        vm.prank(alice);
        vm.expectRevert();
        fl.borrow(posId, 1e18);
    }

    function test_pause_blocksRepay() external {
        _openCorrelatedPosition(alice, INITIAL_COLLATERAL, STANDARD_LTV);
        fl.pause();

        loanToken.mint(alice, 1e18);
        vm.startPrank(alice);
        loanToken.approve(address(fl), 1e18);
        vm.expectRevert();
        fl.repay(alice, 0, 1e18, 0);
        vm.stopPrank();
    }

    function test_pause_blocksWithdrawCollateral() external {
        _openCorrelatedPosition(alice, INITIAL_COLLATERAL, 50e16);
        fl.pause();

        vm.prank(alice);
        vm.expectRevert();
        fl.withdrawCollateral(0, 1e18);
    }

    function test_unpause_resumesOperations() external {
        fl.pause();
        fl.unpause();

        _openCorrelatedPosition(alice, INITIAL_COLLATERAL, STANDARD_LTV);
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

    function test_setMarketEnabled_existingPositionsStillManageable() external {
        uint256 posId = _openCorrelatedPosition(
            alice,
            INITIAL_COLLATERAL,
            50e16
        );

        fl.setMarketEnabled(correlatedMarketId, false);

        // Existing position can still be managed
        LeveragePosition memory pos = fl.getUserLeveragePosition(alice, posId);
        Position memory morphoPos = fl.getMorphoPosition(
            pos.userProxy,
            correlatedMarket
        );

        // Borrow should still work
        vm.prank(alice);
        fl.borrow(posId, 1e17);

        // Deleverage should still work
        morphoPos = fl.getMorphoPosition(pos.userProxy, correlatedMarket);
        uint256 colVal = fl.getCollateralValueInLoanToken(
            correlatedMarket,
            morphoPos.collateral
        );
        SwapData memory swap = _buildSwapData(
            address(collateralToken),
            address(loanToken),
            morphoPos.collateral,
            colVal
        );

        vm.prank(alice);
        fl.deleverage(posId, 0, swap, 0);

        assertFalse(fl.getUserLeveragePosition(alice, posId).open);
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

    function test_addSupportedMarkets_onlyOwner() external {
        MarketConfig[] memory configs = new MarketConfig[](1);
        configs[0] = MarketConfig({
            marketId: correlatedMarketId,
            isCorrelated: true
        });

        vm.prank(alice);
        vm.expectRevert();
        fl.addSupportedMarkets(configs);
    }

    function test_addSupportedMarkets_revertsOnExistingMarket() external {
        MarketConfig[] memory configs = new MarketConfig[](1);
        configs[0] = MarketConfig({
            marketId: correlatedMarketId,
            isCorrelated: false // trying to flip correlated → non-correlated
        });

        vm.expectRevert(FLError.FlashLeverage__MarketAlreadyExists.selector);
        fl.addSupportedMarkets(configs);
    }

    // ═══════════════════════════════════════════════
    //                  FEE UPDATES
    // ═══════════════════════════════════════════════

    function test_updateYieldFee_success() external {
        fl.updateYieldFee(5e16); // 5%
        assertEq(fl.s_yieldFee(), 5e16);
    }

    function test_updateYieldFee_zeroIsAllowed() external {
        fl.updateYieldFee(0);
        assertEq(fl.s_yieldFee(), 0);
    }

    function test_updateYieldFee_revertsAboveMax() external {
        vm.expectRevert(FLError.FlashLeverage__InvalidYieldFee.selector);
        fl.updateYieldFee(11e16); // 11% > 10% max
    }

    function test_updateYieldFee_onlyOwner() external {
        vm.prank(alice);
        vm.expectRevert();
        fl.updateYieldFee(5e16);
    }

    /// @notice Zero deposit fee means no fee charged
    function test_depositFee_zeroFee_noCharge() external {
        fl.updateDepositFee(0);

        uint256 collateral = 100e18;
        uint256 treasuryBefore = ncCollateralToken.balanceOf(treasury);

        _openNonCorrelatedPosition(alice, collateral, 50e16);

        uint256 treasuryAfter = ncCollateralToken.balanceOf(treasury);
        assertEq(treasuryAfter, treasuryBefore, "Zero fee = no charge");
    }

    function test_updateYieldFee_takesEffectImmediately() external {
        uint256 posId = _openCorrelatedPosition(
            alice,
            INITIAL_COLLATERAL,
            STANDARD_LTV
        );

        // 10% appreciation
        correlatedOracle.setPrice((CORRELATED_PRICE * 110) / 100);

        // Reduce yield fee to 5%
        fl.updateYieldFee(5e16);

        LeveragePosition memory pos = fl.getUserLeveragePosition(alice, posId);
        Position memory morphoPos = fl.getMorphoPosition(
            pos.userProxy,
            correlatedMarket
        );
        uint256 colVal = fl.getCollateralValueInLoanToken(
            correlatedMarket,
            morphoPos.collateral
        );
        SwapData memory swap = _buildSwapData(
            address(collateralToken),
            address(loanToken),
            morphoPos.collateral,
            colVal
        );

        uint256 treasuryBefore = loanToken.balanceOf(treasury);

        vm.prank(alice);
        fl.deleverage(posId, 0, swap, 0);

        uint256 fee = loanToken.balanceOf(treasury) - treasuryBefore;
        // Fee should reflect 5%, not 10%
        assertGt(fee, 0, "Should charge fee");

        // Open identical position at 10% fee for comparison
        correlatedOracle.setPrice(CORRELATED_PRICE);
        fl.updateYieldFee(10e16);

        uint256 posId2 = _openCorrelatedPosition(
            alice,
            INITIAL_COLLATERAL,
            STANDARD_LTV
        );
        correlatedOracle.setPrice((CORRELATED_PRICE * 110) / 100);

        LeveragePosition memory pos2 = fl.getUserLeveragePosition(
            alice,
            posId2
        );
        Position memory morphoPos2 = fl.getMorphoPosition(
            pos2.userProxy,
            correlatedMarket
        );
        uint256 colVal2 = fl.getCollateralValueInLoanToken(
            correlatedMarket,
            morphoPos2.collateral
        );
        SwapData memory swap2 = _buildSwapData(
            address(collateralToken),
            address(loanToken),
            morphoPos2.collateral,
            colVal2
        );

        uint256 treasuryBefore2 = loanToken.balanceOf(treasury);
        vm.prank(alice);
        fl.deleverage(posId2, 0, swap2, 0);

        uint256 fee2 = loanToken.balanceOf(treasury) - treasuryBefore2;
        assertGt(fee2, fee, "10% fee should be larger than 5% fee");
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
        fl.updateDepositFee(2e16); // 2% > 1% max
    }

    function test_updateDepositFee_onlyOwner() external {
        vm.prank(alice);
        vm.expectRevert();
        fl.updateDepositFee(5e15);
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

    function test_updateTreasury_takesEffectOnNextFee() external {
        // Enable yield fee (defaults to 0) so a fee is generated on deleverage.
        fl.updateYieldFee(5e16);

        address newTreasury = makeAddr("newTreasury");

        uint256 posId = _openCorrelatedPosition(
            alice,
            INITIAL_COLLATERAL,
            STANDARD_LTV
        );
        correlatedOracle.setPrice((CORRELATED_PRICE * 110) / 100);

        // Change treasury before deleverage
        fl.updateTreasury(newTreasury);

        LeveragePosition memory pos = fl.getUserLeveragePosition(alice, posId);
        Position memory morphoPos = fl.getMorphoPosition(
            pos.userProxy,
            correlatedMarket
        );
        uint256 colVal = fl.getCollateralValueInLoanToken(
            correlatedMarket,
            morphoPos.collateral
        );
        SwapData memory swap = _buildSwapData(
            address(collateralToken),
            address(loanToken),
            morphoPos.collateral,
            colVal
        );

        vm.prank(alice);
        fl.deleverage(posId, 0, swap, 0);

        // Fee should go to new treasury
        assertGt(
            loanToken.balanceOf(newTreasury),
            0,
            "New treasury should receive fee"
        );
        assertEq(
            loanToken.balanceOf(treasury),
            0,
            "Old treasury should receive nothing"
        );
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
        uint256 posId = _openCorrelatedPosition(
            alice,
            INITIAL_COLLATERAL,
            STANDARD_LTV
        );
        LeveragePosition memory pos = fl.getUserLeveragePosition(alice, posId);

        vm.expectRevert(FLError.FlashLeverage__CannotBeUserProxy.selector);
        fl.setSwapRouter(pos.userProxy, true);
    }

    function test_setSwapRouter_revertsOnMorpho() external {
        vm.expectRevert(FLError.FlashLeverage__CannotBeMorpho.selector);
        fl.setSwapRouter(address(morpho), true);
    }

    // ═══════════════════════════════════════════════
    //              MANUAL MODE
    // ═══════════════════════════════════════════════

    function test_enableManualMode_success() external {
        uint256 posId = _openCorrelatedPosition(
            alice,
            INITIAL_COLLATERAL,
            STANDARD_LTV
        );
        LeveragePosition memory pos = fl.getUserLeveragePosition(alice, posId);

        fl.enableManualMode(pos.userProxy);
        assertTrue(UserProxy(pos.userProxy).s_manualMode());
    }

    function test_enableManualMode_blocksFlashLeverage() external {
        uint256 posId = _openCorrelatedPosition(
            alice,
            INITIAL_COLLATERAL,
            STANDARD_LTV
        );
        LeveragePosition memory pos = fl.getUserLeveragePosition(alice, posId);

        fl.enableManualMode(pos.userProxy);

        vm.prank(alice);
        vm.expectRevert();
        fl.increaseLeverage(posId, 1e18, _emptySwap(), 0);
    }

    function test_enableManualMode_onlyOwner() external {
        uint256 posId = _openCorrelatedPosition(
            alice,
            INITIAL_COLLATERAL,
            STANDARD_LTV
        );
        LeveragePosition memory pos = fl.getUserLeveragePosition(alice, posId);

        vm.prank(alice);
        vm.expectRevert();
        fl.enableManualMode(pos.userProxy);
    }

    // ═══════════════════════════════════════════════
    //              RECOVER
    // ═══════════════════════════════════════════════

    function test_recover_sweepsToOwner() external {
        uint256 stuckAmount = 100e18;
        loanToken.mint(address(fl), stuckAmount);

        address contractOwner = fl.owner();
        uint256 ownerBefore = loanToken.balanceOf(contractOwner);

        fl.recover(address(loanToken));

        assertEq(
            loanToken.balanceOf(contractOwner),
            ownerBefore + stuckAmount,
            "Should send to owner, not caller"
        );
        assertEq(loanToken.balanceOf(address(fl)), 0, "FL should be empty");
    }

    function test_recover_zeroBalance_noRevert() external {
        // Should not revert even with 0 balance
        fl.recover(address(loanToken));
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
        vm.expectRevert(
            FLError.FlashLeverage__OwnershipRenunciationDisabled.selector
        );
        fl.renounceOwnership();
    }

    // ─── Internal helpers ───

    function _dummyLeverageParams()
        internal
        view
        returns (LeverageParams memory)
    {
        return
            LeverageParams({
                marketId: correlatedMarketId,
                amountCollateral: INITIAL_COLLATERAL,
                amountFlashLoan: 5e18,
                swapData: _emptySwap(),
                minTokenOut: 0
            });
    }

    function _emptySwap() internal view returns (SwapData memory) {
        return SwapData({extRouter: address(router), extCalldata: ""});
    }
}
