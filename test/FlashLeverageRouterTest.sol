// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IMorpho, MarketParams, Id, Position} from "@morpho/interfaces/IMorpho.sol";

import {FlashLeverage} from "src/core/FlashLeverage/FlashLeverage.sol";
import {MarketConfig} from "src/core/structs/MarketConfig.sol";
import {LeverageParams} from "src/core/structs/LeverageParams.sol";
import {LeveragePosition} from "src/core/structs/LeveragePosition.sol";
import {SwapData} from "src/core/structs/SwapData.sol";
import {Math} from "src/core/libraries/Math.sol";

// NOTE: Import your FlashLeverageRouter here
// import {FlashLeverageRouter} from "src/router/FlashLeverageRouter.sol";
// import {FLRError} from "src/router/FlashLeverageRouter.sol";

import {MockERC20} from "./mocks/MockERC20.sol";
import {MockOracle} from "./mocks/MockOracle.sol";
import {MockExtRouter} from "./mocks/MockExtRouter.sol";
import {MockIrm} from "./mocks/MockIrm.sol";

/// @title FlashLeverageRouterTest
/// @notice Tests for FlashLeverageRouter::swapAndLeverage
/// @dev Uncomment the FlashLeverageRouter import and tests once the router is finalized.
///      This file provides the test structure — adjust imports to match your project.
contract FlashLeverageRouterTest is Test {
    using Math for uint256;

    // Contracts
    FlashLeverage public fl;
    // FlashLeverageRouter public flRouter;
    IMorpho public morpho;
    MockIrm public irm;
    MockOracle public oracle;
    MockExtRouter public swapRouter;
    MockERC20 public collateralToken;
    MockERC20 public loanToken;
    MockERC20 public inputToken; // token user swaps from (e.g. USDC)

    bytes32 public marketId;
    MarketParams public market;
    address public treasury;
    address public alice;

    uint256 public constant ORACLE_PRICE = 1.1e36;
    uint256 public constant LLTV = 945e15;

    function setUp() public {
        treasury = makeAddr("treasury");
        alice = makeAddr("alice");

        collateralToken = new MockERC20("wstETH", "wstETH", 18);
        loanToken = new MockERC20("WETH", "WETH", 18);
        inputToken = new MockERC20("USDC", "USDC", 6);
        oracle = new MockOracle(ORACLE_PRICE);
        irm = new MockIrm();

        // Deploy real Morpho
        address morphoAddress = vm.deployCode(
            "lib/morpho-blue/out/Morpho.sol/Morpho.json",
            abi.encode(address(this))
        );
        morpho = IMorpho(morphoAddress);

        morpho.enableIrm(address(irm));
        morpho.enableLltv(LLTV);

        fl = new FlashLeverage(address(morpho), treasury);
        swapRouter = new MockExtRouter();
        fl.setSwapRouter(address(swapRouter), true);

        market = MarketParams({
            loanToken: address(loanToken),
            collateralToken: address(collateralToken),
            oracle: address(oracle),
            irm: address(irm),
            lltv: LLTV
        });
        marketId = keccak256(abi.encode(market));

        morpho.createMarket(market);

        MarketConfig[] memory configs = new MarketConfig[](1);
        configs[0] = MarketConfig({marketId: marketId, isCorrelated: true});
        fl.addSupportedMarkets(configs);

        // Seed liquidity
        loanToken.mint(address(this), 1_000_000e18);
        loanToken.approve(address(morpho), 1_000_000e18);
        morpho.supply(market, 1_000_000e18, 0, address(this), "");

        // Seed initial shares to prevent inflation attack
        loanToken.mint(address(this), 1e9);
        loanToken.approve(address(morpho), 1e9);
        morpho.supply(market, 1e9, 0, address(0xdEaD), "");

        // Deploy and whitelist FlashLeverageRouter as approved operator
        // flRouter = new FlashLeverageRouter(address(morpho), address(fl));
        // fl.setApprovedOperator(address(flRouter), true);
    }

    // ─── Placeholder tests ───
    // Uncomment and adjust once FlashLeverageRouter is imported

    /*
    function test_swapAndLeverage_erc20_success() external {
        uint256 inputAmount = 1000e6; // 1000 USDC
        uint256 collateralOut = 10e18; // router gives 10 wstETH

        inputToken.mint(alice, inputAmount);
        collateralToken.mint(address(swapRouter), collateralOut);

        SwapData memory swap = SwapData({
            extRouter: address(swapRouter),
            extCalldata: abi.encodeCall(
                MockExtRouter.swap,
                (address(inputToken), address(collateralToken), inputAmount, collateralOut)
            )
        });

        LeverageParams memory params = LeverageParams({
            marketId: marketId,
            amountCollateral: 0, // will be overwritten
            amountFlashLoan: 5e18,
            swapData: SwapData({extRouter: address(swapRouter), extCalldata: ""}),
            minTokenOut: 0
        });

        vm.startPrank(alice);
        inputToken.approve(address(flRouter), inputAmount);
        flRouter.swapAndLeverage(params, address(inputToken), inputAmount, swap, 0);
        vm.stopPrank();

        assertEq(fl.getUserLeveragePositions(alice).length, 1);
    }

    function test_swapAndLeverage_native_success() external {
        vm.deal(alice, 1 ether);

        // Router should accept native ETH
        // ... test with tokenIn = address(0)
    }

    function test_swapAndLeverage_revertsOnZeroAmountIn() external {
        vm.expectRevert(FLRError.FlashLeverageRouter__AmountInCannotBeZero.selector);
        flRouter.swapAndLeverage(
            LeverageParams({marketId: marketId, amountCollateral: 0, amountFlashLoan: 1e18, swapData: SwapData({extRouter: address(0), extCalldata: ""}), minTokenOut: 0}),
            address(inputToken),
            0,
            SwapData({extRouter: address(swapRouter), extCalldata: ""}),
            0
        );
    }

    function test_swapAndLeverage_revertsOnInvalidRouter() external {
        inputToken.mint(alice, 1000e6);
        vm.startPrank(alice);
        inputToken.approve(address(flRouter), 1000e6);

        vm.expectRevert(FLRError.FlashLeverageRouter__InvalidSwapRouter.selector);
        flRouter.swapAndLeverage(
            LeverageParams({marketId: marketId, amountCollateral: 0, amountFlashLoan: 1e18, swapData: SwapData({extRouter: address(0), extCalldata: ""}), minTokenOut: 0}),
            address(inputToken),
            1000e6,
            SwapData({extRouter: makeAddr("badRouter"), extCalldata: ""}),
            0
        );
        vm.stopPrank();
    }

    function test_swapAndLeverage_refundsExcessERC20() external {
        // Test that unconsumed tokenIn is refunded
    }

    function test_swapAndLeverage_refundsExcessNative() external {
        // Test that unconsumed native ETH is refunded
    }

    function test_swapAndLeverage_revertsOnWrongMsgValue_erc20() external {
        // msg.value > 0 with ERC20 tokenIn should revert
    }

    function test_swapAndLeverage_revertsOnWrongMsgValue_native() external {
        // msg.value != amountIn with native tokenIn should revert
    }

    function test_swapAndLeverage_useMsgSenderAsUser() external {
        // Verify position is opened for msg.sender, not a passed onBehalfOf
    }
    */
}
