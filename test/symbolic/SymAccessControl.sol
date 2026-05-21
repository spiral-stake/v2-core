// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

// ─── How to run ───────────────────────────────────────────────────────────────
//   halmos --match-contract SymAccessControl --forge-build-out abi --solver-timeout-assertion 60000
//
// FlashLeverage admin functions control fee rates, treasury address,
// operator whitelist, swap-router whitelist, market enable/disable, and
// pause/unpause. Proving these for ALL possible callers and values is
// stronger than any fuzz campaign — it closes the access-control attack surface.
//
// NOTE: Standalone setup (no TestBase) — all access-control functions are
//       pure storage updates that do not call Morpho, so only FlashLeverage
//       itself needs to be deployed. Uses native assert() + try/catch for
//       Halmos 0.1.x compatibility.
// ─────────────────────────────────────────────────────────────────────────────

import {Test} from "forge-std/Test.sol";
import {FlashLeverage} from "src/core/FlashLeverage/FlashLeverage.sol";
import {MarketParams} from "@morpho/interfaces/IMorpho.sol";
import {FLError} from "src/core/libraries/Error.sol";

contract SymAccessControl is Test {

    FlashLeverage fl;
    address owner;

    // Market params mirroring TestBase constants — used for getMaxLtv proofs
    uint256 constant CORRELATED_LLTV     = 945e15;  // 94.5%
    uint256 constant NON_CORRELATED_LLTV = 86e16;   // 86.0%

    MarketParams correlatedMarket;
    MarketParams nonCorrelatedMarket;

    uint256 constant MAX_YIELD_FEE   = 10e16; // 10%
    uint256 constant MAX_DEPOSIT_FEE = 1e16;  // 1%

    // Stub addresses — only non-zero values are required by the constructor
    address constant STUB_MORPHO   = address(0x1111);
    address constant STUB_TREASURY = address(0x2222);

    function setUp() public {
        owner = address(this);
        fl = new FlashLeverage(owner, STUB_MORPHO, STUB_TREASURY);

        // Minimal market params — only lltv is read by getMaxLtv/getLiqLtv
        correlatedMarket = MarketParams({
            loanToken:       address(0),
            collateralToken: address(0),
            oracle:          address(0),
            irm:             address(0),
            lltv:            CORRELATED_LLTV
        });
        nonCorrelatedMarket = MarketParams({
            loanToken:       address(0),
            collateralToken: address(0),
            oracle:          address(0),
            irm:             address(0),
            lltv:            NON_CORRELATED_LLTV
        });
    }

    // ═══════════════════════════════════════════════════════════════════════
    // updateYieldFee
    // ═══════════════════════════════════════════════════════════════════════

    /// PROPERTY: Any non-owner caller is rejected — for all possible fee values.
    /// WHY: yield fee controls what fraction of profits go to the protocol.
    ///      An attacker setting it to 100% would steal all user yield.
    function check_updateYieldFee_nonOwnerReverts(
        address caller,
        uint256 fee
    ) external {
        vm.assume(caller != owner);
        vm.assume(fee > 0 && fee <= MAX_YIELD_FEE);
        vm.prank(caller);
        bool reverted;
        try fl.updateYieldFee(fee) {
            reverted = false;
        } catch {
            reverted = true;
        }
        assert(reverted);
    }

    /// PROPERTY: A zero fee ALWAYS reverts — even when called by owner.
    /// WHY: Zero yield fee would disable protocol revenue collection.
    ///      The protocol enforces non-zero.
    function check_updateYieldFee_zeroReverts() external {
        bool reverted;
        try fl.updateYieldFee(0) {
            reverted = false;
        } catch {
            reverted = true;
        }
        assert(reverted);
    }

    /// PROPERTY: A fee above MAX_YIELD_FEE always reverts — for any caller.
    /// WHY: Proves that even if the owner key is compromised, it is impossible
    ///      to set a yield fee above 10%. This is a hard protocol cap.
    function check_updateYieldFee_tooHighReverts(uint256 fee) external {
        vm.assume(fee > MAX_YIELD_FEE);
        bool reverted;
        try fl.updateYieldFee(fee) {
            reverted = false;
        } catch {
            reverted = true;
        }
        assert(reverted);
    }

    /// PROPERTY: After a valid fee update, s_yieldFee == the value passed in.
    /// WHY: No truncation or rounding may occur — the fee stored must exactly
    ///      match what governance set.
    function check_updateYieldFee_storedEqualsSet(uint256 fee) external {
        vm.assume(fee > 0 && fee <= MAX_YIELD_FEE);
        fl.updateYieldFee(fee);
        assert(fl.s_yieldFee() == fee);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // updateDepositFee
    // ═══════════════════════════════════════════════════════════════════════

    /// PROPERTY: Any non-owner caller is rejected for all valid deposit fees.
    function check_updateDepositFee_nonOwnerReverts(
        address caller,
        uint256 fee
    ) external {
        vm.assume(caller != owner);
        vm.assume(fee <= MAX_DEPOSIT_FEE);
        vm.prank(caller);
        bool reverted;
        try fl.updateDepositFee(fee) {
            reverted = false;
        } catch {
            reverted = true;
        }
        assert(reverted);
    }

    /// PROPERTY: A fee above MAX_DEPOSIT_FEE always reverts — for any caller.
    /// WHY: Deposit fee > 1% would make the protocol predatory.
    ///      This hard cap cannot be bypassed even by the owner key.
    function check_updateDepositFee_tooHighReverts(uint256 fee) external {
        vm.assume(fee > MAX_DEPOSIT_FEE);
        bool reverted;
        try fl.updateDepositFee(fee) {
            reverted = false;
        } catch {
            reverted = true;
        }
        assert(reverted);
    }

    /// PROPERTY: After a valid deposit fee update, s_depositFee == value passed.
    function check_updateDepositFee_storedEqualsSet(uint256 fee) external {
        vm.assume(fee <= MAX_DEPOSIT_FEE);
        fl.updateDepositFee(fee);
        assert(fl.s_depositFee() == fee);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // updateTreasury
    // ═══════════════════════════════════════════════════════════════════════

    /// PROPERTY: Setting treasury to address(0) always reverts.
    /// WHY: Zero treasury would make all fee transfers succeed (0 address
    ///      accepts tokens) but the funds would be permanently burned.
    function check_updateTreasury_zeroAddressReverts() external {
        bool reverted;
        try fl.updateTreasury(address(0)) {
            reverted = false;
        } catch {
            reverted = true;
        }
        assert(reverted);
    }

    /// PROPERTY: Any non-owner caller is rejected for all non-zero addresses.
    function check_updateTreasury_nonOwnerReverts(
        address caller,
        address newTreasury
    ) external {
        vm.assume(caller != owner);
        vm.assume(newTreasury != address(0));
        vm.prank(caller);
        bool reverted;
        try fl.updateTreasury(newTreasury) {
            reverted = false;
        } catch {
            reverted = true;
        }
        assert(reverted);
    }

    /// PROPERTY: After a valid treasury update, s_treasury == the value passed.
    function check_updateTreasury_storedEqualsSet(address newTreasury) external {
        vm.assume(newTreasury != address(0));
        fl.updateTreasury(newTreasury);
        assert(fl.s_treasury() == newTreasury);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // setApprovedOperator
    // ═══════════════════════════════════════════════════════════════════════

    /// PROPERTY: Approving the zero address always reverts.
    /// WHY: address(0) as an operator would create a logic hole in authorization.
    function check_setApprovedOperator_zeroAddressReverts(bool value) external {
        bool reverted;
        try fl.setApprovedOperator(address(0), value) {
            reverted = false;
        } catch {
            reverted = true;
        }
        assert(reverted);
    }

    /// PROPERTY: Any non-owner caller is rejected.
    /// WHY: Operator approval gates who can open leveraged positions on behalf
    ///      of users. An unauthorized approval could let an attacker drain
    ///      user collateral through a malicious "operator."
    function check_setApprovedOperator_nonOwnerReverts(
        address caller,
        address operator,
        bool value
    ) external {
        vm.assume(caller != owner);
        vm.assume(operator != address(0));
        vm.prank(caller);
        bool reverted;
        try fl.setApprovedOperator(operator, value) {
            reverted = false;
        } catch {
            reverted = true;
        }
        assert(reverted);
    }

    /// PROPERTY: After approval, the stored flag matches what was set.
    function check_setApprovedOperator_storedEqualsSet(
        address operator,
        bool value
    ) external {
        vm.assume(operator != address(0));
        fl.setApprovedOperator(operator, value);
        assert(fl.s_approvedOperators(operator) == value);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // pause / unpause
    // ═══════════════════════════════════════════════════════════════════════

    /// PROPERTY: Any caller that is not the owner cannot pause.
    /// WHY: Pause is an emergency control. An attacker who can pause could
    ///      DoS the entire protocol.
    function check_pause_unauthorizedReverts(address caller) external {
        vm.assume(caller != owner);
        vm.prank(caller);
        bool reverted;
        try fl.pause() {
            reverted = false;
        } catch {
            reverted = true;
        }
        assert(reverted);
    }

    /// PROPERTY: Any non-owner caller cannot unpause.
    /// WHY: unpause requires a deliberate governance decision by the owner.
    function check_unpause_nonOwnerReverts(address caller) external {
        fl.pause();
        vm.assume(caller != owner);
        vm.prank(caller);
        bool reverted;
        try fl.unpause() {
            reverted = false;
        } catch {
            reverted = true;
        }
        assert(reverted);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // renounceOwnership (permanently disabled)
    // ═══════════════════════════════════════════════════════════════════════

    /// PROPERTY: renounceOwnership ALWAYS reverts — regardless of caller.
    /// WHY: If ownership were renounced, all admin functions would be
    ///      permanently bricked. The protocol deliberately disables this OZ
    ///      function. Proving it for ALL callers means even the deployer
    ///      cannot do it.
    function check_renounceOwnership_alwaysReverts(address caller) external {
        vm.prank(caller);
        bool reverted;
        try fl.renounceOwnership() {
            reverted = false;
        } catch {
            reverted = true;
        }
        assert(reverted);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // getMaxLtv — computed value correctness
    // ═══════════════════════════════════════════════════════════════════════

    /// PROPERTY: getMaxLtv(market) == market.lltv - LIQUIDATION_BUFFER
    ///           for both supported markets.
    /// WHY: getMaxLtv underlies every LTV check in leverage() and borrow().
    ///      If the formula is wrong, positions could be opened above liquidation
    ///      threshold — exactly the scenario that causes protocol insolvency.
    function check_getMaxLtv_equalsLltvMinusBuffer() external view {
        uint256 liqBuffer = fl.LIQUIDATION_BUFFER();
        assert(fl.getMaxLtv(correlatedMarket)    == correlatedMarket.lltv    - liqBuffer);
        assert(fl.getMaxLtv(nonCorrelatedMarket) == nonCorrelatedMarket.lltv - liqBuffer);
    }

    /// PROPERTY: getMaxLtv is always strictly less than the market LLTV.
    /// WHY: maxLtv < LLTV is the safety buffer that prevents new positions from
    ///      being immediately liquidatable.
    function check_getMaxLtv_strictlyBelowLltv() external view {
        assert(fl.getMaxLtv(correlatedMarket)    < correlatedMarket.lltv);
        assert(fl.getMaxLtv(nonCorrelatedMarket) < nonCorrelatedMarket.lltv);
    }
}
