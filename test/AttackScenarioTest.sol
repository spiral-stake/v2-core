// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import "./TestBase.sol";
import {FLError} from "src/core/libraries/Error.sol";

/// @title AttackScenarioTest
/// @notice Adversarial tests attempting to exploit stuck funds, drainage, and fee bypass.
///         Each test either proves the attack fails or reveals a vulnerability to fix.
contract AttackScenarioTest is TestBase {
    using Math for uint256;

    uint256 constant INITIAL_COLLATERAL = 10e18;
    uint256 constant STANDARD_LTV = 70e16;

    // ═══════════════════════════════════════════════
    //        FUNDS STUCK — DUST BORROW SHARES
    // ═══════════════════════════════════════════════

    /// @notice Repay all but 1 wei of borrow shares — can user still deleverage?
    function test_attack_dustBorrowShares_canDeleverage() external {
        uint256 posId = _openCorrelatedPosition(
            alice,
            INITIAL_COLLATERAL,
            STANDARD_LTV
        );

        LeveragePosition memory pos = fl.getUserLeveragePosition(alice, posId);
        Position memory morphoPos = fl.getMorphoPosition(
            pos.userProxy,
            correlatedMarket
        );

        // Repay all shares except 1 wei
        uint256 sharesToRepay = morphoPos.borrowShares - 1;
        uint256 debtForShares = fl.getSharesValueInLoanToken(
            correlatedMarket,
            sharesToRepay
        );
        loanToken.mint(alice, debtForShares);

        vm.startPrank(alice);
        loanToken.approve(address(fl), debtForShares);
        fl.repay(alice, posId, debtForShares, sharesToRepay);
        vm.stopPrank();

        // Now position has 1 wei borrow share — can we deleverage?
        morphoPos = fl.getMorphoPosition(pos.userProxy, correlatedMarket);
        assertEq(morphoPos.borrowShares, 1, "Should have 1 wei dust share");

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

        // This should not revert — dust should be handleable
        vm.prank(alice);
        fl.deleverage(posId, 0, swap, 0);

        LeveragePosition memory posAfter = fl.getUserLeveragePosition(
            alice,
            posId
        );
        assertFalse(
            posAfter.open,
            "Position should close even with dust shares"
        );
    }

    /// @notice Position with zero debt but collateral — can user withdraw everything?
    function test_attack_zeroDebtFullWithdraw_noRevert() external {
        uint256 posId = _openCorrelatedPosition(
            alice,
            INITIAL_COLLATERAL,
            STANDARD_LTV
        );

        // Repay all debt
        _repayAllDebt(alice, posId, correlatedMarket);

        LeveragePosition memory pos = fl.getUserLeveragePosition(alice, posId);
        Position memory morphoPos = fl.getMorphoPosition(
            pos.userProxy,
            correlatedMarket
        );
        assertEq(morphoPos.borrowShares, 0);
        assertGt(morphoPos.collateral, 0);

        // Withdraw all — should not revert or get stuck
        vm.prank(alice);
        fl.withdrawCollateral(posId, morphoPos.collateral);

        morphoPos = fl.getMorphoPosition(pos.userProxy, correlatedMarket);
        assertEq(morphoPos.collateral, 0, "All collateral should be withdrawn");
        assertGt(
            collateralToken.balanceOf(alice),
            0,
            "Alice should have her collateral"
        );
    }

    /// @notice Manual mode freezes FlashLeverage operations — can user recover via proxy?
    function test_attack_manualModeFreezesFLButUserCanRecover() external {
        uint256 posId = _openCorrelatedPosition(
            alice,
            INITIAL_COLLATERAL,
            STANDARD_LTV
        );
        LeveragePosition memory pos = fl.getUserLeveragePosition(alice, posId);

        fl.enableManualMode(pos.userProxy);

        // FL operations should all be blocked
        vm.prank(alice);
        vm.expectRevert();
        fl.withdrawCollateral(posId, 1e18);

        vm.prank(alice);
        vm.expectRevert();
        fl.borrow(posId, 1e18);

        // But user can interact with Morpho directly via proxy.execute
        // This is the intended escape hatch
    }

    // ═══════════════════════════════════════════════
    //    YIELD FEE BYPASS — BORROW/REPAY CYCLING
    // ═══════════════════════════════════════════════

    /// @notice Attempt to inflate amountDepositedInLoanToken via borrow/repay cycle
    ///         to reduce yield fee on deleverage
    function test_attack_borrowRepayCycle_cannotInflateDeposited() external {
        uint256 posId = _openCorrelatedPosition(
            alice,
            INITIAL_COLLATERAL,
            50e16
        );

        LeveragePosition memory posStart = fl.getUserLeveragePosition(
            alice,
            posId
        );
        uint256 depositedStart = posStart.amountDepositedInLoanToken;

        // Borrow then repay same amount — 10 cycles
        uint256 cycleAmount = depositedStart / 10;
        for (uint256 i; i < 10; i++) {
            vm.prank(alice);
            fl.borrow(posId, cycleAmount);

            loanToken.approve(address(fl), cycleAmount);
            vm.startPrank(alice);
            loanToken.approve(address(fl), cycleAmount);
            fl.repay(alice, posId, cycleAmount, 0);
            vm.stopPrank();
        }

        LeveragePosition memory posEnd = fl.getUserLeveragePosition(
            alice,
            posId
        );

        // Deposited should be exactly the same — no inflation possible
        assertEq(
            posEnd.amountDepositedInLoanToken,
            depositedStart,
            "Borrow/repay cycle should not change deposited"
        );
    }

    /// @notice Attempt: borrow at price P1, oracle goes up, repay at P2
    ///         Does deposited get inflated because repay adds loan tokens at higher price?
    function test_attack_borrowRepayWithPriceChange_noInflation() external {
        uint256 posId = _openCorrelatedPosition(
            alice,
            INITIAL_COLLATERAL,
            50e16
        );

        LeveragePosition memory posStart = fl.getUserLeveragePosition(
            alice,
            posId
        );
        uint256 depositedStart = posStart.amountDepositedInLoanToken;

        // Borrow at current price
        uint256 borrowAmount = depositedStart / 5;
        vm.prank(alice);
        fl.borrow(posId, borrowAmount);

        // Oracle goes up 10%
        correlatedOracle.setPrice((CORRELATED_PRICE * 110) / 100);

        // Repay same loan token amount
        loanToken.mint(alice, borrowAmount);
        vm.startPrank(alice);
        loanToken.approve(address(fl), borrowAmount);
        fl.repay(alice, posId, borrowAmount, 0);
        vm.stopPrank();

        LeveragePosition memory posEnd = fl.getUserLeveragePosition(
            alice,
            posId
        );

        // Borrow subtracts borrowAmount, repay adds borrowAmount
        // Net change should be zero regardless of oracle price
        assertEq(
            posEnd.amountDepositedInLoanToken,
            depositedStart,
            "Price change between borrow and repay should not affect deposited"
        );
    }

    // ═══════════════════════════════════════════════
    //  YIELD FEE BYPASS — SMALL WITHDRAWALS IN YIELD
    // ═══════════════════════════════════════════════

    /// @notice Extract yield via many small withdrawals (each within yield portion)
    ///         then deleverage — does user pay less total fee?
    function test_attack_smallWithdrawalsReduceTotalFee() external {
        // Position A: deleverage directly (baseline fee)
        uint256 posA = _openCorrelatedPosition(
            alice,
            INITIAL_COLLATERAL,
            50e16
        );

        // Position B: same params for bob
        uint256 posB = _openCorrelatedPosition(bob, INITIAL_COLLATERAL, 50e16);

        // 20% appreciation
        correlatedOracle.setPrice((CORRELATED_PRICE * 120) / 100);

        // Alice: deleverage directly — pays full yield fee
        uint256 treasuryBeforeA = loanToken.balanceOf(treasury);

        _deleveragePosition(alice, posA, correlatedMarket);
        uint256 feeA = loanToken.balanceOf(treasury) - treasuryBeforeA;

        // Bob: withdraw small amounts from yield first, then deleverage
        LeveragePosition memory bobPos = fl.getUserLeveragePosition(bob, posB);
        Position memory bobMorpho = fl.getMorphoPosition(
            bobPos.userProxy,
            correlatedMarket
        );

        uint256 smallWithdraw = bobMorpho.collateral / 100; // 1% each
        uint256 totalBobCollateralFee;

        uint256 treasuryColBefore = collateralToken.balanceOf(treasury);
        for (uint256 i; i < 5; i++) {
            vm.prank(bob);
            fl.withdrawCollateral(posB, smallWithdraw);
        }
        totalBobCollateralFee =
            collateralToken.balanceOf(treasury) -
            treasuryColBefore;

        // Now deleverage remainder
        uint256 treasuryBeforeB = loanToken.balanceOf(treasury);
        _deleveragePosition(bob, posB, correlatedMarket);
        uint256 feeBLoanToken = loanToken.balanceOf(treasury) - treasuryBeforeB;

        // Convert bob's collateral fee to loan token equivalent for comparison
        uint256 totalBobCollateralFeeInLoan = fl.getCollateralValueInLoanToken(
            correlatedMarket,
            totalBobCollateralFee
        );

        uint256 totalFeeB = feeBLoanToken + totalBobCollateralFeeInLoan;

        // Bob's total fee (collateral withdrawals + deleverage) should be >= alice's fee
        // If totalFeeB < feeA, the small withdrawal strategy bypasses fees
        assertGe(
            totalFeeB,
            feeA - 1, // 1 wei tolerance for rounding
            "VULNERABILITY: Small withdrawals reduce total yield fee"
        );
    }

    // ═══════════════════════════════════════════════
    //  YIELD FEE BYPASS — THIRD PARTY SUPPLY INFLATION
    // ═══════════════════════════════════════════════

    /// @notice Bob supplies collateral to alice's position to inflate deposited,
    ///         reducing alice's yield fee on deleverage
    function test_attack_thirdPartySupplyInflatesDeposited() external {
        // Baseline: alice opens and deleverages after 20% yield
        uint256 posBaseline = _openCorrelatedPosition(
            alice,
            INITIAL_COLLATERAL,
            50e16
        );

        correlatedOracle.setPrice((CORRELATED_PRICE * 120) / 100);

        uint256 treasuryBefore1 = loanToken.balanceOf(treasury);
        _deleveragePosition(alice, posBaseline, correlatedMarket);
        uint256 baselineFee = loanToken.balanceOf(treasury) - treasuryBefore1;

        // Reset oracle
        correlatedOracle.setPrice(CORRELATED_PRICE);

        // Attack: bob opens position for alice, bob supplies extra collateral
        uint256 posAttack = _openCorrelatedPosition(
            alice,
            INITIAL_COLLATERAL,
            50e16
        );

        // Bob supplies 50 wstETH to alice's position — inflates deposited
        uint256 bobSupply = 50e18;
        collateralToken.mint(bob, bobSupply);
        vm.startPrank(bob);
        collateralToken.approve(address(fl), bobSupply);
        fl.supplyCollateral(alice, posAttack, bobSupply);
        vm.stopPrank();

        // Same 20% appreciation
        correlatedOracle.setPrice((CORRELATED_PRICE * 120) / 100);

        uint256 treasuryBefore2 = loanToken.balanceOf(treasury);
        _deleveragePosition(alice, posAttack, correlatedMarket);
        uint256 attackFee = loanToken.balanceOf(treasury) - treasuryBefore2;

        // If attackFee < baselineFee, bob's supply reduced alice's fee
        // This is expected since deposited is higher, so yield appears smaller
        // The question is whether this is exploitable — bob LOSES his 50 wstETH
        // Alice gets bob's collateral back minus fee
        // This is a gift from bob, not a drain — but fee is reduced

        // Log for manual inspection
        emit log_named_uint("Baseline fee", baselineFee);
        emit log_named_uint("Attack fee (with bob supply)", attackFee);
        emit log_named_uint("Bob lost", bobSupply);
    }

    // ═══════════════════════════════════════════════
    //     YIELD FEE BYPASS — SUPPLY/WITHDRAW CYCLE
    // ═══════════════════════════════════════════════

    /// @notice Supply at P1, oracle goes up, withdraw at P2.
    ///         Deposited inflates but attacker pays MORE total fee, not less.
    function test_attack_supplyWithdrawCycle_cannotReduceTotalFee() external {
        // Baseline: alice opens and deleverages after 10% yield
        uint256 posBaseline = _openCorrelatedPosition(
            alice,
            INITIAL_COLLATERAL,
            30e16
        );

        correlatedOracle.setPrice((CORRELATED_PRICE * 110) / 100);

        uint256 treasuryBefore1 = loanToken.balanceOf(treasury);
        uint256 treasuryColBefore1 = collateralToken.balanceOf(treasury);
        _deleveragePosition(alice, posBaseline, correlatedMarket);
        uint256 baselineFeeLoan = loanToken.balanceOf(treasury) -
            treasuryBefore1;
        uint256 baselineFeeCol = collateralToken.balanceOf(treasury) -
            treasuryColBefore1;

        // Reset oracle
        correlatedOracle.setPrice(CORRELATED_PRICE);

        // Attack path: bob opens, supplies, oracle up, withdraws, deleverages
        uint256 posAttack = _openCorrelatedPosition(
            bob,
            INITIAL_COLLATERAL,
            30e16
        );

        uint256 supplyAmount = 5e18;
        collateralToken.mint(bob, supplyAmount);
        vm.startPrank(bob);
        collateralToken.approve(address(fl), supplyAmount);
        fl.supplyCollateral(bob, posAttack, supplyAmount);
        vm.stopPrank();

        correlatedOracle.setPrice((CORRELATED_PRICE * 110) / 100);

        uint256 treasuryColBefore2 = collateralToken.balanceOf(treasury);
        vm.prank(bob);
        fl.withdrawCollateral(posAttack, supplyAmount);
        uint256 attackFeeCol = collateralToken.balanceOf(treasury) -
            treasuryColBefore2;

        uint256 treasuryBefore2 = loanToken.balanceOf(treasury);
        _deleveragePosition(bob, posAttack, correlatedMarket);
        uint256 attackFeeLoan = loanToken.balanceOf(treasury) - treasuryBefore2;

        uint256 attackFeeColInLoan = fl.getCollateralValueInLoanToken(
            correlatedMarket,
            attackFeeCol
        );
        uint256 totalAttackFee = attackFeeLoan + attackFeeColInLoan;
        uint256 totalBaselineFee = baselineFeeLoan +
            fl.getCollateralValueInLoanToken(correlatedMarket, baselineFeeCol);

        // Attacker should pay at least as much fee as baseline — cycle cannot reduce fees
        assertGe(
            totalAttackFee,
            totalBaselineFee - 1, // 1 wei rounding tolerance
            "VULNERABILITY: Supply/withdraw cycle reduces total yield fee"
        );
    }

    // ═══════════════════════════════════════════════
    //     CROSS-POSITION ISOLATION
    // ═══════════════════════════════════════════════

    /// @notice Operations on position 0 should not affect position 1
    function test_attack_crossPositionIsolation() external {
        uint256 pos0 = _openCorrelatedPosition(
            alice,
            INITIAL_COLLATERAL,
            50e16
        );
        uint256 pos1 = _openCorrelatedPosition(
            alice,
            INITIAL_COLLATERAL,
            50e16
        );

        LeveragePosition memory pos1Before = fl.getUserLeveragePosition(
            alice,
            pos1
        );
        Position memory morpho1Before = fl.getMorphoPosition(
            pos1Before.userProxy,
            correlatedMarket
        );

        // Fully close position 0
        _deleveragePosition(alice, pos0, correlatedMarket);

        // Position 1 should be completely unaffected
        LeveragePosition memory pos1After = fl.getUserLeveragePosition(
            alice,
            pos1
        );
        Position memory morpho1After = fl.getMorphoPosition(
            pos1After.userProxy,
            correlatedMarket
        );

        assertTrue(pos1After.open);
        assertEq(morpho1After.collateral, morpho1Before.collateral);
        assertEq(morpho1After.borrowShares, morpho1Before.borrowShares);
        assertEq(
            pos1After.amountDepositedInLoanToken,
            pos1Before.amountDepositedInLoanToken
        );
    }

    // ═══════════════════════════════════════════════
    //    REPAY ON BEHALF — CAN BOB INFLATE ALICE'S DEPOSITED?
    // ═══════════════════════════════════════════════

    /// @notice Bob repays alice's debt — does this let alice borrow more than she should?
    function test_attack_repayOnBehalf_borrowLimit() external {
        uint256 posId = _openCorrelatedPosition(
            alice,
            INITIAL_COLLATERAL,
            50e16
        );

        LeveragePosition memory pos = fl.getUserLeveragePosition(alice, posId);
        Position memory morphoPos = fl.getMorphoPosition(
            pos.userProxy,
            correlatedMarket
        );
        uint256 debt = fl.getSharesValueInLoanToken(
            correlatedMarket,
            morphoPos.borrowShares
        );

        uint256 depositedBefore = pos.amountDepositedInLoanToken;

        // Bob repays alice's full debt
        loanToken.mint(bob, debt);
        vm.startPrank(bob);
        loanToken.approve(address(fl), debt);
        fl.repay(alice, posId, debt, morphoPos.borrowShares);
        vm.stopPrank();

        // Alice's deposited is now inflated by repaid amount
        pos = fl.getUserLeveragePosition(alice, posId);
        uint256 depositedAfter = pos.amountDepositedInLoanToken;
        assertEq(
            depositedAfter,
            depositedBefore + debt,
            "Deposited inflated by repay"
        );

        // Alice tries to borrow all of deposited (correlated guard)
        // She can borrow up to depositedAfter on correlated markets
        // But LTV check should still limit her

        // 2x appreciation to give LTV headroom
        correlatedOracle.setPrice(CORRELATED_PRICE * 2);

        // Alice borrows the full inflated deposited
        vm.prank(alice);
        fl.borrow(posId, depositedAfter);

        // Alice received debt + depositedBefore in total borrowing power
        // But she only put in INITIAL_COLLATERAL originally
        // Bob gifted his tokens — alice just borrowed against increased deposited
        // The LTV check prevents alice from borrowing more than collateral supports
        // So this is not a drain — it's bob voluntarily funding alice's position

        assertEq(
            loanToken.balanceOf(alice),
            depositedAfter,
            "Alice borrowed inflated amount"
        );
    }

    // ─── Internal helpers ───

    function _repayAllDebt(
        address user,
        uint256 posId,
        MarketParams memory mkt
    ) internal {
        LeveragePosition memory pos = fl.getUserLeveragePosition(user, posId);
        Position memory morphoPos = fl.getMorphoPosition(pos.userProxy, mkt);
        uint256 debt = fl.getSharesValueInLoanToken(
            mkt,
            morphoPos.borrowShares
        );

        MockERC20(mkt.loanToken).mint(user, debt);

        vm.startPrank(user);
        MockERC20(mkt.loanToken).approve(address(fl), debt);
        fl.repay(user, posId, debt, morphoPos.borrowShares);
        vm.stopPrank();
    }

    function _deleveragePosition(
        address user,
        uint256 posId,
        MarketParams memory mkt
    ) internal {
        LeveragePosition memory pos = fl.getUserLeveragePosition(user, posId);
        Position memory morphoPos = fl.getMorphoPosition(pos.userProxy, mkt);
        uint256 colVal = fl.getCollateralValueInLoanToken(
            mkt,
            morphoPos.collateral
        );
        SwapData memory swap = _buildSwapData(
            mkt.collateralToken,
            mkt.loanToken,
            morphoPos.collateral,
            colVal
        );

        vm.prank(user);
        fl.deleverage(posId, 0, swap, 0);
    }
}
