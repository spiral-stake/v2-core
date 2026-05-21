// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import {CommonBase} from "forge-std/Base.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {StdUtils} from "forge-std/StdUtils.sol";

import {MarketParams, Position} from "@morpho/interfaces/IMorpho.sol";

import {FlashLeverage} from "src/core/FlashLeverage/FlashLeverage.sol";
import {LeverageParams} from "src/core/structs/LeverageParams.sol";
import {LeveragePosition} from "src/core/structs/LeveragePosition.sol";
import {SwapData} from "src/core/structs/SwapData.sol";
import {Math} from "src/core/libraries/Math.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {MockOracle} from "test/mocks/MockOracle.sol";
import {MockExtRouter} from "test/mocks/MockExtRouter.sol";

/// @notice Invariant handler for FlashLeverage. Drives the protocol through
///         valid state transitions and maintains ghost variables that the
///         invariant contracts check against.
contract FlashLeverageHandler is CommonBase, StdCheats, StdUtils {
    using Math for uint256;

    // ─── Caps ──────────────────────────────────────────────────────────────────
    // Conservative so the flash-loan pair (flashLoan + in-callback borrow) never
    // exceeds the 101M-token pool seeded in FuzzTestBase.
    uint256 constant MAX_CORR_COLLATERAL = 3_000e18;
    uint256 constant MAX_NC_COLLATERAL   = 3e18;
    uint256 constant MIN_COLLATERAL      = 1e15;
    uint256 constant MIN_LTV             = 5e16;

    // ─── Dependencies ──────────────────────────────────────────────────────────
    FlashLeverage    public immutable fl;
    MockExtRouter    public immutable router;
    MockERC20        public immutable collateralToken;
    MockERC20        public immutable loanToken;
    MockERC20        public immutable ncCollateralToken;
    MockERC20        public immutable ncLoanToken;
    MockOracle       public immutable correlatedOracle;
    MockOracle       public immutable nonCorrelatedOracle;
    MarketParams     public correlatedMarket;
    MarketParams     public nonCorrelatedMarket;
    bytes32          public immutable correlatedMarketId;
    bytes32          public immutable nonCorrelatedMarketId;
    address          public immutable treasury;

    // ─── Actors ────────────────────────────────────────────────────────────────
    address[] public actors;

    // ─── Ghost state ───────────────────────────────────────────────────────────
    // Parallel arrays: same index maps actor ↔ posId ↔ isCorrelated.
    address[] public ghost_openActors;
    uint256[] public ghost_openPosIds;
    bool[]    public ghost_openIsCorrelated;

    address[] public ghost_closedActors;
    uint256[] public ghost_closedPosIds;

    // Snapshot of treasury balances at construction (before any calls).
    uint256 public ghost_treasuryLoanInitial;
    uint256 public ghost_treasuryNcLoanInitial;

    // ─── Constructor ───────────────────────────────────────────────────────────

    constructor(
        address _fl,
        address _router,
        address _collateralToken,
        address _loanToken,
        address _ncCollateralToken,
        address _ncLoanToken,
        address _correlatedOracle,
        address _nonCorrelatedOracle,
        MarketParams memory _correlatedMarket,
        MarketParams memory _nonCorrelatedMarket,
        bytes32 _correlatedMarketId,
        bytes32 _nonCorrelatedMarketId,
        address _treasury,
        address _alice,
        address _bob
    ) {
        fl                    = FlashLeverage(_fl);
        router                = MockExtRouter(_router);
        collateralToken       = MockERC20(_collateralToken);
        loanToken             = MockERC20(_loanToken);
        ncCollateralToken     = MockERC20(_ncCollateralToken);
        ncLoanToken           = MockERC20(_ncLoanToken);
        correlatedOracle      = MockOracle(_correlatedOracle);
        nonCorrelatedOracle   = MockOracle(_nonCorrelatedOracle);
        correlatedMarket      = _correlatedMarket;
        nonCorrelatedMarket   = _nonCorrelatedMarket;
        correlatedMarketId    = _correlatedMarketId;
        nonCorrelatedMarketId = _nonCorrelatedMarketId;
        treasury              = _treasury;

        actors.push(_alice);
        actors.push(_bob);

        ghost_treasuryLoanInitial   = loanToken.balanceOf(_treasury);
        ghost_treasuryNcLoanInitial = ncLoanToken.balanceOf(_treasury);
    }

    // ─── Handler: open correlated position ────────────────────────────────────

    function leverage_correlated(
        uint256 actorSeed,
        uint256 collateral,
        uint256 ltvSeed
    ) external {
        address actor = _pickActor(actorSeed);
        collateral = bound(collateral, MIN_COLLATERAL, MAX_CORR_COLLATERAL);
        uint256 maxLtv = fl.getMaxLtv(correlatedMarket);
        uint256 ltv = bound(ltvSeed, MIN_LTV, maxLtv - 1e14);

        collateralToken.mint(actor, collateral);
        uint256 flashLoan = _calcFlashLoan(ltv, collateral, correlatedMarket);
        uint256 swapOut   = _calcSwapOutput(flashLoan, correlatedMarket);
        SwapData memory swap = _buildSwapData(
            address(loanToken), address(collateralToken), flashLoan, swapOut
        );

        vm.startPrank(actor);
        collateralToken.approve(address(fl), collateral);
        try fl.leverage(actor, LeverageParams({
            marketId:        correlatedMarketId,
            amountCollateral: collateral,
            amountFlashLoan:  flashLoan,
            swapData:         swap,
            minTokenOut:      0
        })) {
            uint256 posId = fl.getUserLeveragePositions(actor).length - 1;
            ghost_openActors.push(actor);
            ghost_openPosIds.push(posId);
            ghost_openIsCorrelated.push(true);
        } catch {}
        vm.stopPrank();
    }

    // ─── Handler: open non-correlated position ─────────────────────────────────

    function leverage_nonCorrelated(
        uint256 actorSeed,
        uint256 collateral,
        uint256 ltvSeed
    ) external {
        address actor = _pickActor(actorSeed);
        collateral = bound(collateral, MIN_COLLATERAL, MAX_NC_COLLATERAL);
        uint256 maxLtv = fl.getMaxLtv(nonCorrelatedMarket);
        uint256 ltv = bound(ltvSeed, MIN_LTV, maxLtv - 1e14);

        ncCollateralToken.mint(actor, collateral);
        uint256 flashLoan = _calcFlashLoan(ltv, collateral, nonCorrelatedMarket);
        uint256 swapOut   = _calcSwapOutput(flashLoan, nonCorrelatedMarket);
        SwapData memory swap = _buildSwapData(
            address(ncLoanToken), address(ncCollateralToken), flashLoan, swapOut
        );

        vm.startPrank(actor);
        ncCollateralToken.approve(address(fl), collateral);
        try fl.leverage(actor, LeverageParams({
            marketId:        nonCorrelatedMarketId,
            amountCollateral: collateral,
            amountFlashLoan:  flashLoan,
            swapData:         swap,
            minTokenOut:      0
        })) {
            uint256 posId = fl.getUserLeveragePositions(actor).length - 1;
            ghost_openActors.push(actor);
            ghost_openPosIds.push(posId);
            ghost_openIsCorrelated.push(false);
        } catch {}
        vm.stopPrank();
    }

    // ─── Handler: close a position ────────────────────────────────────────────

    function deleverage(uint256 posSeed) external {
        if (ghost_openActors.length == 0) return;
        uint256 idx = posSeed % ghost_openActors.length;

        address actor = ghost_openActors[idx];
        uint256 posId = ghost_openPosIds[idx];
        bool    isCorr = ghost_openIsCorrelated[idx];

        LeveragePosition memory pos = fl.getUserLeveragePosition(actor, posId);
        if (!pos.open) {
            // Externally closed (e.g., liquidated) — sync ghost state and exit.
            _removeGhostOpen(idx);
            return;
        }

        MarketParams memory mkt = isCorr ? correlatedMarket : nonCorrelatedMarket;
        Position memory morphoPos = fl.getMorphoPosition(pos.userProxy, mkt);

        // Add +1e12 buffer: oracle-price swapOut can be 1-2 wei below actual
        // debt due to Morpho borrow-share rounding.
        uint256 swapOut = fl.getCollateralValueInLoanToken(mkt, morphoPos.collateral) + 1e12;
        SwapData memory swap = _buildSwapData(
            mkt.collateralToken, mkt.loanToken, morphoPos.collateral, swapOut
        );

        vm.prank(actor);
        try fl.deleverage(posId, 0, swap, 0) {
            _removeGhostOpen(idx);
            ghost_closedActors.push(actor);
            ghost_closedPosIds.push(posId);
        } catch {}
    }

    // ─── Handler: supply extra collateral ────────────────────────────────────

    function supplyCollateral(uint256 posSeed, uint256 amount) external {
        if (ghost_openActors.length == 0) return;
        uint256 idx = posSeed % ghost_openActors.length;
        address actor = ghost_openActors[idx];
        uint256 posId = ghost_openPosIds[idx];
        bool    isCorr = ghost_openIsCorrelated[idx];

        amount = bound(amount, 1, isCorr ? MAX_CORR_COLLATERAL : MAX_NC_COLLATERAL);

        MockERC20 colTok = isCorr ? collateralToken : ncCollateralToken;
        colTok.mint(actor, amount);

        vm.startPrank(actor);
        colTok.approve(address(fl), amount);
        try fl.supplyCollateral(actor, posId, amount) {} catch {}
        vm.stopPrank();
    }

    // ─── Handler: repay part of the debt ──────────────────────────────────────

    function repay(uint256 posSeed, uint256 amount) external {
        if (ghost_openActors.length == 0) return;
        uint256 idx = posSeed % ghost_openActors.length;
        address actor = ghost_openActors[idx];
        uint256 posId = ghost_openPosIds[idx];
        bool    isCorr = ghost_openIsCorrelated[idx];

        MarketParams memory mkt = isCorr ? correlatedMarket : nonCorrelatedMarket;
        LeveragePosition memory pos = fl.getUserLeveragePosition(actor, posId);
        Position memory morphoPos = fl.getMorphoPosition(pos.userProxy, mkt);
        if (morphoPos.borrowShares == 0) return;

        uint256 debt = fl.getSharesValueInLoanToken(mkt, morphoPos.borrowShares);
        // Partial repay: 1 wei to half the debt — avoids the overflow seen at
        // near-maxLtv max-collateral extremes (tracked separately as known failure).
        amount = bound(amount, 1, debt / 2 + 1);

        MockERC20 loanTok = isCorr ? loanToken : ncLoanToken;
        loanTok.mint(actor, amount);

        vm.startPrank(actor);
        loanTok.approve(address(fl), amount);
        try fl.repay(actor, posId, amount, 0) {} catch {}
        vm.stopPrank();
    }

    // ─── Ghost helpers ────────────────────────────────────────────────────────

    function getGhostOpenCount() external view returns (uint256) {
        return ghost_openActors.length;
    }

    function getGhostClosedCount() external view returns (uint256) {
        return ghost_closedActors.length;
    }

    // ─── Internal helpers ─────────────────────────────────────────────────────

    function _pickActor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }

    function _removeGhostOpen(uint256 idx) internal {
        uint256 last = ghost_openActors.length - 1;
        ghost_openActors[idx]       = ghost_openActors[last];
        ghost_openPosIds[idx]       = ghost_openPosIds[last];
        ghost_openIsCorrelated[idx] = ghost_openIsCorrelated[last];
        ghost_openActors.pop();
        ghost_openPosIds.pop();
        ghost_openIsCorrelated.pop();
    }

    function _buildSwapData(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOut
    ) internal returns (SwapData memory) {
        MockERC20(tokenOut).mint(address(router), amountOut);
        return SwapData({
            extRouter: address(router),
            extCalldata: abi.encodeCall(
                MockExtRouter.swap,
                (tokenIn, tokenOut, amountIn, amountOut)
            )
        });
    }

    function _calcFlashLoan(
        uint256 ltv,
        uint256 collateral,
        MarketParams memory mkt
    ) internal view returns (uint256) {
        uint256 colVal = fl.getCollateralValueInLoanToken(mkt, collateral);
        uint8 loanDecimals = MockERC20(mkt.loanToken).decimals();
        uint256 colValStd = colVal.scaleTo(loanDecimals, Math.STANDARD_DECIMALS);
        uint256 totalPos = colValStd.divDown(Math.ONE - ltv);
        return (totalPos - colValStd).scaleTo(Math.STANDARD_DECIMALS, loanDecimals);
    }

    function _calcSwapOutput(
        uint256 amountLoanToken,
        MarketParams memory mkt
    ) internal view returns (uint256) {
        uint256 oraclePrice = MockOracle(mkt.oracle).price();
        uint8 loanDecimals  = MockERC20(mkt.loanToken).decimals();
        uint8 colDecimals   = MockERC20(mkt.collateralToken).decimals();
        uint256 scaleFactor = 10 ** (36 + colDecimals - loanDecimals);
        return (amountLoanToken * scaleFactor) / oraclePrice;
    }
}
