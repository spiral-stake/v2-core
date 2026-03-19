// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IMorpho, MarketParams, Id, Position} from "@morpho/interfaces/IMorpho.sol";

import {FlashLeverage} from "src/core/FlashLeverage/FlashLeverage.sol";
import {MarketConfig} from "src/core/structs/MarketConfig.sol";
import {LeverageParams} from "src/core/structs/LeverageParams.sol";
import {LeveragePosition} from "src/core/structs/LeveragePosition.sol";
import {SwapData} from "src/core/structs/SwapData.sol";
import {Math} from "src/core/libraries/Math.sol";

import {MockERC20} from "./mocks/MockERC20.sol";
import {MockOracle} from "./mocks/MockOracle.sol";
import {MockExtRouter} from "./mocks/MockExtRouter.sol";
import {MockIrm} from "./mocks/MockIrm.sol";

/// @title TestBase
/// @notice Shared setup for all FlashLeverage test suites.
///         Deploys the REAL Morpho contract from lib/morpho-blue,
///         mock tokens, oracles, and IRM for testing.
///
/// @dev Morpho (solidity 0.8.19) is deployed via vm.deployCode to handle
///      the version mismatch with FlashLeverage (0.8.30).
///      Add this to foundry.toml if not already present:
///        solc_version = "0.8.30"
///        additional_compiler_profiles = [{ name = "morpho", via_ir = false, solc_version = "0.8.19" }]
///        compilation_restrictions = [{ paths = "lib/morpho-blue/src/**", profile = "morpho" }]
abstract contract TestBase is Test {
    using Math for uint256;

    // ─── Contracts ───
    FlashLeverage public fl;
    IMorpho public morpho;
    MockOracle public correlatedOracle;
    MockOracle public nonCorrelatedOracle;
    MockExtRouter public router;
    MockIrm public irm;
    MockERC20 public collateralToken; // e.g. wstETH
    MockERC20 public loanToken; // e.g. WETH
    MockERC20 public ncCollateralToken; // e.g. ETH for non-correlated
    MockERC20 public ncLoanToken; // e.g. USDC

    // ─── Market params ───
    bytes32 public correlatedMarketId;
    MarketParams public correlatedMarket;
    bytes32 public nonCorrelatedMarketId;
    MarketParams public nonCorrelatedMarket;

    // ─── Addresses ───
    address public treasury;
    address public alice;
    address public bob;
    address public owner;

    // ─── Constants ───
    /// @dev Oracle price for correlated pair: 1 collateral = 1.1 loan token
    ///      Morpho oracle price is scaled to 1e36 for 18-decimal pairs
    uint256 public constant CORRELATED_PRICE = 1.1e36;

    /// @dev Oracle price for non-correlated pair: 1 collateral = 2000 loan token (e.g. ETH/USDC)
    ///      Scaled for 18-decimal collateral and 6-decimal loan: 1e(36+6-18) = 1e24 scale
    uint256 public constant NON_CORRELATED_PRICE = 2000e24;

    /// @dev Correlated market LLTV: 94.5%
    uint256 public constant CORRELATED_LLTV = 945e15;

    /// @dev Non-correlated market LLTV: 86%
    uint256 public constant NON_CORRELATED_LLTV = 86e16;

    uint256 public constant INITIAL_LIQUIDITY = 1_000_000e18;
    uint256 public constant NC_INITIAL_LIQUIDITY = 1_000_000e6;

    function setUp() public virtual {
        // ─── Deploy actors ───
        owner = address(this);
        treasury = makeAddr("treasury");
        alice = makeAddr("alice");
        bob = makeAddr("bob");

        // ─── Deploy tokens ───
        collateralToken = new MockERC20("Wrapped Staked ETH", "wstETH", 18);
        loanToken = new MockERC20("Wrapped ETH", "WETH", 18);
        ncCollateralToken = new MockERC20("Ether", "ETH", 18);
        ncLoanToken = new MockERC20("USD Coin", "USDC", 6);

        // ─── Deploy oracles ───
        correlatedOracle = new MockOracle(CORRELATED_PRICE);
        nonCorrelatedOracle = new MockOracle(NON_CORRELATED_PRICE);

        // ─── Deploy IRM ───
        irm = new MockIrm();

        // ─── Deploy real Morpho ───
        // Morpho is compiled with solidity 0.8.19, deployed via vm.deployCode
        address morphoAddress = vm.deployCode(
            "lib/morpho-blue/out/Morpho.sol/Morpho.json",
            abi.encode(owner)
        );
        morpho = IMorpho(morphoAddress);

        // Enable IRM and LLTVs on Morpho
        morpho.enableIrm(address(irm));
        morpho.enableLltv(CORRELATED_LLTV);
        morpho.enableLltv(NON_CORRELATED_LLTV);

        // ─── Deploy FlashLeverage ───
        fl = new FlashLeverage(address(morpho), treasury);

        // ─── Deploy and whitelist router ───
        router = new MockExtRouter();
        fl.setSwapRouter(address(router), true);

        // ─── Setup correlated market (wstETH/WETH, 94.5% LLTV) ───
        correlatedMarket = MarketParams({
            loanToken: address(loanToken),
            collateralToken: address(collateralToken),
            oracle: address(correlatedOracle),
            irm: address(irm),
            lltv: CORRELATED_LLTV
        });
        correlatedMarketId = keccak256(abi.encode(correlatedMarket));

        // Create market on Morpho
        morpho.createMarket(correlatedMarket);

        // Register market on FlashLeverage
        MarketConfig[] memory correlatedConfigs = new MarketConfig[](1);
        correlatedConfigs[0] = MarketConfig({
            marketId: correlatedMarketId,
            isCorrelated: true
        });
        fl.addSupportedMarkets(correlatedConfigs);

        // ─── Setup non-correlated market (ETH/USDC, 86% LLTV) ───
        nonCorrelatedMarket = MarketParams({
            loanToken: address(ncLoanToken),
            collateralToken: address(ncCollateralToken),
            oracle: address(nonCorrelatedOracle),
            irm: address(irm),
            lltv: NON_CORRELATED_LLTV
        });
        nonCorrelatedMarketId = keccak256(abi.encode(nonCorrelatedMarket));

        // Create market on Morpho
        morpho.createMarket(nonCorrelatedMarket);

        // Register market on FlashLeverage
        MarketConfig[] memory ncConfigs = new MarketConfig[](1);
        ncConfigs[0] = MarketConfig({
            marketId: nonCorrelatedMarketId,
            isCorrelated: false
        });
        fl.addSupportedMarkets(ncConfigs);

        // ─── Seed Morpho with lender liquidity ───
        _seedLiquidity(correlatedMarket, INITIAL_LIQUIDITY, loanToken);
        _seedLiquidity(nonCorrelatedMarket, NC_INITIAL_LIQUIDITY, ncLoanToken);

        // ─── Seed initial shares to prevent inflation attack ───
        _seedInitialShares(correlatedMarket, loanToken);
        _seedInitialShares(nonCorrelatedMarket, ncLoanToken);
    }

    // ─── Internal setup helpers ───

    function _seedLiquidity(
        MarketParams memory mkt,
        uint256 amount,
        MockERC20 token
    ) internal {
        address supplier = makeAddr("supplier");
        token.mint(supplier, amount);
        vm.startPrank(supplier);
        token.approve(address(morpho), amount);
        morpho.supply(mkt, amount, 0, supplier, "");
        vm.stopPrank();
    }

    /// @dev Seed 1e9 shares to dead address to prevent inflation front-running
    ///      as recommended by Morpho docs
    function _seedInitialShares(
        MarketParams memory mkt,
        MockERC20 token
    ) internal {
        uint256 seedAmount = 1e9;
        address dead = address(0xdEaD);
        token.mint(address(this), seedAmount);
        token.approve(address(morpho), seedAmount);
        morpho.supply(mkt, seedAmount, 0, dead, "");
    }

    // ─── Helpers ───

    /// @notice Build swap data for a full swap via MockExtRouter
    function _buildSwapData(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOut
    ) internal returns (SwapData memory) {
        // Pre-fund the router with tokenOut
        MockERC20(tokenOut).mint(address(router), amountOut);

        return SwapData({
            extRouter: address(router),
            extCalldata: abi.encodeCall(
                MockExtRouter.swap,
                (tokenIn, tokenOut, amountIn, amountOut)
            )
        });
    }

    /// @notice Calculate flash loan amount for a target LTV
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

    /// @notice Calculate expected collateral output from a flash loan swap
    function _calcSwapOutput(
        uint256 amountLoanToken,
        MarketParams memory mkt
    ) internal view returns (uint256) {
        uint256 oraclePrice = MockOracle(mkt.oracle).price();
        uint8 loanDecimals = MockERC20(mkt.loanToken).decimals();
        uint8 colDecimals = MockERC20(mkt.collateralToken).decimals();

        uint256 scaleFactor = 10 ** (36 + colDecimals - loanDecimals);
        return (amountLoanToken * scaleFactor) / oraclePrice;
    }

    /// @notice Open a correlated leveraged position for a user
    function _openCorrelatedPosition(
        address user,
        uint256 collateralAmount,
        uint256 targetLtv
    ) internal returns (uint256 positionId) {
        collateralToken.mint(user, collateralAmount);

        uint256 flashLoan = _calcFlashLoan(targetLtv, collateralAmount, correlatedMarket);
        uint256 swapOut = _calcSwapOutput(flashLoan, correlatedMarket);
        SwapData memory swap = _buildSwapData(
            address(loanToken),
            address(collateralToken),
            flashLoan,
            swapOut
        );

        vm.startPrank(user);
        collateralToken.approve(address(fl), collateralAmount);
        fl.leverage(
            user,
            LeverageParams({
                marketId: correlatedMarketId,
                amountCollateral: collateralAmount,
                amountFlashLoan: flashLoan,
                swapData: swap,
                minTokenOut: 0
            })
        );
        vm.stopPrank();

        positionId = fl.getUserLeveragePositions(user).length - 1;
    }

    /// @notice Open a non-correlated leveraged position for a user
    function _openNonCorrelatedPosition(
        address user,
        uint256 collateralAmount,
        uint256 targetLtv
    ) internal returns (uint256 positionId) {
        ncCollateralToken.mint(user, collateralAmount);

        uint256 flashLoan = _calcFlashLoan(targetLtv, collateralAmount, nonCorrelatedMarket);
        uint256 swapOut = _calcSwapOutput(flashLoan, nonCorrelatedMarket);
        SwapData memory swap = _buildSwapData(
            address(ncLoanToken),
            address(ncCollateralToken),
            flashLoan,
            swapOut
        );

        vm.startPrank(user);
        ncCollateralToken.approve(address(fl), collateralAmount);
        fl.leverage(
            user,
            LeverageParams({
                marketId: nonCorrelatedMarketId,
                amountCollateral: collateralAmount,
                amountFlashLoan: flashLoan,
                swapData: swap,
                minTokenOut: 0
            })
        );
        vm.stopPrank();

        positionId = fl.getUserLeveragePositions(user).length - 1;
    }

    /// @notice Get the Morpho position for a user's leverage position
    function _getMorphoPosition(
        address user,
        uint256 positionId,
        MarketParams memory mkt
    ) internal view returns (Position memory) {
        LeveragePosition memory pos = fl.getUserLeveragePosition(user, positionId);
        return fl.getMorphoPosition(pos.userProxy, mkt);
    }
}
