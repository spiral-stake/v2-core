// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import "./TestBase.sol";
import {FLError} from "src/core/libraries/Error.sol";

// NOTE: Uncomment when router contract is finalized
import {FLRError, FlashLeverageRouter} from "src/router/FlashLeverageRouter.sol";

/// @title FlashLeverageRouterTest
/// @notice Tests for FlashLeverageRouter::swapAndLeverage
/// @dev Uncomment imports and tests once router contract is finalized.
///      Tests are written from expected behavior, not implementation.
contract FlashLeverageRouterTest is TestBase {
    using Math for uint256;

    uint256 constant INITIAL_COLLATERAL = 10e18;
    uint256 constant STANDARD_LTV = 70e16; // 70%

    FlashLeverageRouter public flRouter;
    MockERC20 public inputToken; // e.g. USDC — token user starts with

    function setUp() public override {
        super.setUp();

        inputToken = new MockERC20("USD Coin", "USDC", 6);

        // Deploy router
        flRouter = new FlashLeverageRouter(address(morpho), address(fl));

        // Router must be approved operator on FL
        fl.setApprovedOperator(address(flRouter), true);

        // Whitelist the swap router on FL (already done in TestBase for `router`)
    }

    // ═══════════════════════════════════════════════
    //              ERC20 HAPPY PATH
    // ═══════════════════════════════════════════════

    function test_swapAndLeverage_erc20_fullVerification() external {
        uint256 inputAmount = 1000e6; // 1000 USDC
        uint256 collateralFromSwap = 10e18; // swap gives 10 wstETH

        // Build swap: USDC → wstETH (pre-leverage swap on router)
        collateralToken.mint(address(router), collateralFromSwap);
        SwapData memory preSwap = SwapData({
            extRouter: address(router),
            extCalldata: abi.encodeCall(
                MockExtRouter.swap,
                (
                    address(inputToken),
                    address(collateralToken),
                    inputAmount,
                    collateralFromSwap
                )
            )
        });

        // Build swap: WETH → wstETH (leverage swap inside FL)
        uint256 flashLoan = _calcFlashLoan(
            STANDARD_LTV,
            collateralFromSwap,
            correlatedMarket
        );
        uint256 leverageSwapOut = _calcSwapOutput(flashLoan, correlatedMarket);
        SwapData memory leverageSwap = _buildSwapData(
            address(loanToken),
            address(collateralToken),
            flashLoan,
            leverageSwapOut
        );

        inputToken.mint(alice, inputAmount);

        uint256 aliceInputBefore = inputToken.balanceOf(alice);

        vm.startPrank(alice);
        inputToken.approve(address(flRouter), inputAmount);
        flRouter.swapAndLeverage(
            LeverageParams({
                marketId: correlatedMarketId,
                amountCollateral: collateralFromSwap,
                amountFlashLoan: flashLoan,
                swapData: leverageSwap,
                minTokenOut: 0
            }),
            address(inputToken),
            inputAmount,
            preSwap,
            0
        );
        vm.stopPrank();

        // Position opened for msg.sender (alice), not a passed onBehalfOf
        assertEq(fl.getUserLeveragePositions(alice).length, 1);

        LeveragePosition memory pos = fl.getUserLeveragePosition(alice, 0);
        assertTrue(pos.open);

        // Input tokens pulled from alice
        assertEq(inputToken.balanceOf(alice), aliceInputBefore - inputAmount);

        // No tokens left in router
        assertEq(inputToken.balanceOf(address(flRouter)), 0);
        assertEq(collateralToken.balanceOf(address(flRouter)), 0);
        assertEq(loanToken.balanceOf(address(flRouter)), 0);
    }

    function test_swapAndLeverage_erc20_positionOwnedByMsgSender() external {
        uint256 inputAmount = 1000e6;
        uint256 collateralFromSwap = 10e18;

        collateralToken.mint(address(router), collateralFromSwap);
        SwapData memory preSwap = SwapData({
            extRouter: address(router),
            extCalldata: abi.encodeCall(
                MockExtRouter.swap,
                (
                    address(inputToken),
                    address(collateralToken),
                    inputAmount,
                    collateralFromSwap
                )
            )
        });

        uint256 flashLoan = _calcFlashLoan(
            STANDARD_LTV,
            collateralFromSwap,
            correlatedMarket
        );
        uint256 leverageSwapOut = _calcSwapOutput(flashLoan, correlatedMarket);
        SwapData memory leverageSwap = _buildSwapData(
            address(loanToken),
            address(collateralToken),
            flashLoan,
            leverageSwapOut
        );

        inputToken.mint(alice, inputAmount);

        vm.startPrank(alice);
        inputToken.approve(address(flRouter), inputAmount);
        flRouter.swapAndLeverage(
            LeverageParams({
                marketId: correlatedMarketId,
                amountCollateral: collateralFromSwap,
                amountFlashLoan: flashLoan,
                swapData: leverageSwap,
                minTokenOut: 0
            }),
            address(inputToken),
            inputAmount,
            preSwap,
            0
        );
        vm.stopPrank();

        // Position belongs to alice (msg.sender), nobody else has positions
        assertEq(fl.getUserLeveragePositions(alice).length, 1);
        assertEq(fl.getUserLeveragePositions(bob).length, 0);
        assertEq(fl.getUserLeveragePositions(address(flRouter)).length, 0);
    }

    // ═══════════════════════════════════════════════
    //              NATIVE ETH HAPPY PATH
    // ═══════════════════════════════════════════════

    function test_swapAndLeverage_native_fullVerification() external {
        uint256 ethAmount = 1 ether;
        uint256 collateralFromSwap = 10e18;

        // Pre-fund router for the swap output
        collateralToken.mint(address(router), collateralFromSwap);
        SwapData memory preSwap = SwapData({
            extRouter: address(router),
            extCalldata: abi.encodeCall(
                MockExtRouter.swapETH,
                (address(collateralToken), ethAmount, collateralFromSwap)
            )
        });

        uint256 flashLoan = _calcFlashLoan(
            STANDARD_LTV,
            collateralFromSwap,
            correlatedMarket
        );
        uint256 leverageSwapOut = _calcSwapOutput(flashLoan, correlatedMarket);
        SwapData memory leverageSwap = _buildSwapData(
            address(loanToken),
            address(collateralToken),
            flashLoan,
            leverageSwapOut
        );

        vm.deal(alice, ethAmount);
        uint256 aliceEthBefore = alice.balance;

        vm.prank(alice);
        flRouter.swapAndLeverage{value: ethAmount}(
            LeverageParams({
                marketId: correlatedMarketId,
                amountCollateral: collateralFromSwap,
                amountFlashLoan: flashLoan,
                swapData: leverageSwap,
                minTokenOut: 0
            }),
            address(0), // native ETH
            ethAmount,
            preSwap,
            0
        );

        assertEq(fl.getUserLeveragePositions(alice).length, 1);
        assertEq(
            alice.balance,
            aliceEthBefore - ethAmount,
            "ETH should be consumed"
        );
        assertEq(address(flRouter).balance, 0, "No ETH left in router");
    }

    // ═══════════════════════════════════════════════
    //              REFUND EXCESS
    // ═══════════════════════════════════════════════

    function test_swapAndLeverage_erc20_refundsExcess() external {
        uint256 inputAmount = 1000e6;
        uint256 actualConsumed = 800e6; // swap only uses 800
        uint256 collateralFromSwap = 8e18;

        collateralToken.mint(address(router), collateralFromSwap);
        SwapData memory preSwap = SwapData({
            extRouter: address(router),
            extCalldata: abi.encodeCall(
                MockExtRouter.swap,
                (
                    address(inputToken),
                    address(collateralToken),
                    actualConsumed,
                    collateralFromSwap
                )
            )
        });

        uint256 flashLoan = _calcFlashLoan(
            STANDARD_LTV,
            collateralFromSwap,
            correlatedMarket
        );
        uint256 leverageSwapOut = _calcSwapOutput(flashLoan, correlatedMarket);
        SwapData memory leverageSwap = _buildSwapData(
            address(loanToken),
            address(collateralToken),
            flashLoan,
            leverageSwapOut
        );

        inputToken.mint(alice, inputAmount);

        vm.startPrank(alice);
        inputToken.approve(address(flRouter), inputAmount);
        flRouter.swapAndLeverage(
            LeverageParams({
                marketId: correlatedMarketId,
                amountCollateral: collateralFromSwap,
                amountFlashLoan: flashLoan,
                swapData: leverageSwap,
                minTokenOut: 0
            }),
            address(inputToken),
            inputAmount,
            preSwap,
            0
        );
        vm.stopPrank();

        uint256 expectedRefund = inputAmount - actualConsumed;
        assertEq(
            inputToken.balanceOf(alice),
            expectedRefund,
            "Should refund unconsumed input tokens"
        );
        assertEq(
            inputToken.balanceOf(address(flRouter)),
            0,
            "No tokens left in router"
        );
    }

    function test_swapAndLeverage_native_refundsExcess() external {
        uint256 ethSent = 2 ether;
        uint256 actualConsumed = 1 ether;
        uint256 collateralFromSwap = 10e18;

        collateralToken.mint(address(router), collateralFromSwap);
        SwapData memory preSwap = SwapData({
            extRouter: address(router),
            extCalldata: abi.encodeCall(
                MockExtRouter.swapETH,
                (address(collateralToken), actualConsumed, collateralFromSwap)
            )
        });

        uint256 flashLoan = _calcFlashLoan(
            STANDARD_LTV,
            collateralFromSwap,
            correlatedMarket
        );
        uint256 leverageSwapOut = _calcSwapOutput(flashLoan, correlatedMarket);
        SwapData memory leverageSwap = _buildSwapData(
            address(loanToken),
            address(collateralToken),
            flashLoan,
            leverageSwapOut
        );

        vm.deal(alice, ethSent);
        uint256 aliceEthBefore = alice.balance;

        vm.prank(alice);
        flRouter.swapAndLeverage{value: ethSent}(
            LeverageParams({
                marketId: correlatedMarketId,
                amountCollateral: collateralFromSwap,
                amountFlashLoan: flashLoan,
                swapData: leverageSwap,
                minTokenOut: 0
            }),
            address(0),
            ethSent,
            preSwap,
            0
        );

        assertEq(
            alice.balance,
            aliceEthBefore - actualConsumed,
            "Should refund excess ETH"
        );
        assertEq(address(flRouter).balance, 0, "No ETH left in router");
    }

    // ═══════════════════════════════════════════════
    //           MSG.VALUE VALIDATION
    // ═══════════════════════════════════════════════

    function test_swapAndLeverage_erc20_revertsOnNonZeroMsgValue() external {
        inputToken.mint(alice, 1000e6);

        vm.deal(alice, 1 ether);
        vm.startPrank(alice);
        inputToken.approve(address(flRouter), 1000e6);

        vm.expectRevert();
        flRouter.swapAndLeverage{value: 1 ether}(
            LeverageParams({
                marketId: correlatedMarketId,
                amountCollateral: 10e18,
                amountFlashLoan: 5e18,
                swapData: _emptySwap(),
                minTokenOut: 0
            }),
            address(inputToken), // ERC20, not native
            1000e6,
            _emptySwap(),
            0
        );
        vm.stopPrank();
    }

    function test_swapAndLeverage_native_revertsOnMsgValueMismatch() external {
        vm.deal(alice, 2 ether);

        vm.prank(alice);
        vm.expectRevert();
        flRouter.swapAndLeverage{value: 1 ether}(
            LeverageParams({
                marketId: correlatedMarketId,
                amountCollateral: 10e18,
                amountFlashLoan: 5e18,
                swapData: _emptySwap(),
                minTokenOut: 0
            }),
            address(0), // native
            2 ether, // amountIn != msg.value
            _emptySwap(),
            0
        );
    }

    // ═══════════════════════════════════════════════
    //              REVERT CASES
    // ═══════════════════════════════════════════════

    function test_swapAndLeverage_revertsOnZeroAmountIn() external {
        vm.prank(alice);
        vm.expectRevert();
        flRouter.swapAndLeverage(
            LeverageParams({
                marketId: correlatedMarketId,
                amountCollateral: 10e18,
                amountFlashLoan: 5e18,
                swapData: _emptySwap(),
                minTokenOut: 0
            }),
            address(inputToken),
            0,
            _emptySwap(),
            0
        );
    }

    function test_swapAndLeverage_revertsOnUnsupportedMarket() external {
        uint256 inputAmount = 1000e6;
        uint256 collateralFromSwap = 10e18;

        collateralToken.mint(address(router), collateralFromSwap);
        SwapData memory preSwap = SwapData({
            extRouter: address(router),
            extCalldata: abi.encodeCall(
                MockExtRouter.swap,
                (
                    address(inputToken),
                    address(collateralToken),
                    inputAmount,
                    collateralFromSwap
                )
            )
        });

        inputToken.mint(alice, inputAmount);

        vm.startPrank(alice);
        inputToken.approve(address(flRouter), inputAmount);

        vm.expectRevert();
        flRouter.swapAndLeverage(
            LeverageParams({
                marketId: keccak256("fake"),
                amountCollateral: collateralFromSwap,
                amountFlashLoan: 5e18,
                swapData: _emptySwap(),
                minTokenOut: 0
            }),
            address(inputToken),
            inputAmount,
            preSwap,
            0
        );
        vm.stopPrank();
    }

    function test_swapAndLeverage_revertsOnInvalidPreSwapRouter() external {
        inputToken.mint(alice, 1000e6);

        vm.startPrank(alice);
        inputToken.approve(address(flRouter), 1000e6);

        vm.expectRevert();
        flRouter.swapAndLeverage(
            LeverageParams({
                marketId: correlatedMarketId,
                amountCollateral: 10e18,
                amountFlashLoan: 5e18,
                swapData: _emptySwap(),
                minTokenOut: 0
            }),
            address(inputToken),
            1000e6,
            SwapData({extRouter: makeAddr("badRouter"), extCalldata: ""}),
            0
        );
        vm.stopPrank();
    }

    function test_swapAndLeverage_revertsWhenRouterNotApprovedOperator()
        external
    {
        // Remove router as approved operator
        // fl.setApprovedOperator(address(flRouter), false);

        inputToken.mint(alice, 1000e6);

        vm.startPrank(alice);
        inputToken.approve(address(flRouter), 1000e6);

        vm.expectRevert();
        flRouter.swapAndLeverage(
            LeverageParams({
                marketId: correlatedMarketId,
                amountCollateral: 10e18,
                amountFlashLoan: 5e18,
                swapData: _emptySwap(),
                minTokenOut: 0
            }),
            address(inputToken),
            1000e6,
            _emptySwap(),
            0
        );
        vm.stopPrank();
    }

    // ─── Internal helpers ───

    function _emptySwap() internal view returns (SwapData memory) {
        return SwapData({extRouter: address(router), extCalldata: ""});
    }
}
