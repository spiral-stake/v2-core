// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import "./TestBase.sol";
import {FLError} from "src/core/libraries/Error.sol";
import {FLRError, FlashLeverageRouter, ReallocateParams} from "src/router/FlashLeverageRouter.sol";
import {MockPublicAllocator} from "./mocks/MockPublicAllocator.sol";
import {Withdrawal, MarketParams as SupplyMarketParams} from "@morpho-public-allocator/interfaces/IPublicAllocator.sol";

/// @title FlashLeverageRouterTest
/// @notice Tests for FlashLeverageRouter
contract FlashLeverageRouterTest is TestBase {
    using Math for uint256;

    uint256 constant INITIAL_COLLATERAL = 10e18;
    uint256 constant STANDARD_LTV = 70e16;

    FlashLeverageRouter public flRouter;
    MockPublicAllocator public mockAllocator;
    MockERC20 public inputToken;

    function setUp() public override {
        super.setUp();

        inputToken = new MockERC20("USD Coin", "USDC", 6);
        mockAllocator = new MockPublicAllocator();

        flRouter = new FlashLeverageRouter(
            address(morpho),
            address(mockAllocator),
            address(fl)
        );

        fl.setApprovedOperator(address(flRouter), true);
    }

    // ═══════════════════════════════════════════════
    //              ERC20 HAPPY PATH
    // ═══════════════════════════════════════════════

    function test_swapAndLeverage_erc20_fullVerification() external {
        uint256 inputAmount = 1000e6;
        uint256 collateralFromSwap = 10e18;

        (
            SwapData memory preSwap,
            LeverageParams memory params
        ) = _buildFullSwapParams(inputAmount, collateralFromSwap);

        inputToken.mint(alice, inputAmount);
        uint256 aliceInputBefore = inputToken.balanceOf(alice);

        vm.startPrank(alice);
        inputToken.approve(address(flRouter), inputAmount);
        flRouter.swapAndLeverage(
            address(inputToken),
            inputAmount,
            preSwap,
            0,
            params
        );
        vm.stopPrank();

        assertEq(fl.getUserLeveragePositions(alice).length, 1);
        assertTrue(fl.getUserLeveragePosition(alice, 0).open);
        assertEq(inputToken.balanceOf(alice), aliceInputBefore - inputAmount);
        assertEq(inputToken.balanceOf(address(flRouter)), 0);
        assertEq(collateralToken.balanceOf(address(flRouter)), 0);
        assertEq(loanToken.balanceOf(address(flRouter)), 0);
    }

    function test_swapAndLeverage_erc20_positionOwnedByMsgSender() external {
        uint256 inputAmount = 1000e6;
        uint256 collateralFromSwap = 10e18;

        (
            SwapData memory preSwap,
            LeverageParams memory params
        ) = _buildFullSwapParams(inputAmount, collateralFromSwap);

        inputToken.mint(alice, inputAmount);

        vm.startPrank(alice);
        inputToken.approve(address(flRouter), inputAmount);
        flRouter.swapAndLeverage(
            address(inputToken),
            inputAmount,
            preSwap,
            0,
            params
        );
        vm.stopPrank();

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

        (
            SwapData memory preSwap,
            LeverageParams memory params
        ) = _buildNativeSwapParams(ethAmount, collateralFromSwap);

        vm.deal(alice, ethAmount);
        uint256 aliceEthBefore = alice.balance;

        vm.prank(alice);
        flRouter.swapAndLeverage{value: ethAmount}(
            address(0),
            ethAmount,
            preSwap,
            0,
            params
        );

        assertEq(fl.getUserLeveragePositions(alice).length, 1);
        assertEq(alice.balance, aliceEthBefore - ethAmount);
        assertEq(address(flRouter).balance, 0);
    }

    // ═══════════════════════════════════════════════
    //              REFUND EXCESS
    // ═══════════════════════════════════════════════

    function test_swapAndLeverage_erc20_refundsExcess() external {
        uint256 inputAmount = 1000e6;
        uint256 actualConsumed = 800e6;
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
            address(inputToken),
            inputAmount,
            preSwap,
            0,
            LeverageParams({
                marketId: correlatedMarketId,
                amountCollateral: collateralFromSwap,
                amountFlashLoan: flashLoan,
                swapData: leverageSwap,
                minTokenOut: 0
            })
        );
        vm.stopPrank();

        assertEq(inputToken.balanceOf(alice), inputAmount - actualConsumed);
        assertEq(inputToken.balanceOf(address(flRouter)), 0);
    }

    function test_swapAndLeverage_native_refundsExcess() external {
        uint256 ethSent = 2 ether;
        uint256 actualConsumed = 1 ether;
        uint256 collateralFromSwap = 10e18;

        (
            SwapData memory preSwap,
            LeverageParams memory params
        ) = _buildNativeSwapParams(actualConsumed, collateralFromSwap);

        vm.deal(alice, ethSent);
        uint256 aliceEthBefore = alice.balance;

        vm.prank(alice);
        flRouter.swapAndLeverage{value: ethSent}(
            address(0),
            ethSent,
            preSwap,
            0,
            params
        );

        assertEq(alice.balance, aliceEthBefore - actualConsumed);
        assertEq(address(flRouter).balance, 0);
    }

    // ═══════════════════════════════════════════════
    //           MSG.VALUE VALIDATION
    // ═══════════════════════════════════════════════

    function test_swapAndLeverage_erc20_revertsOnNonZeroMsgValue() external {
        inputToken.mint(alice, 1000e6);
        vm.deal(alice, 1 ether);

        vm.startPrank(alice);
        inputToken.approve(address(flRouter), 1000e6);

        vm.expectRevert(FLRError.FlashLeverageRouter__InvalidMsgValue.selector);
        flRouter.swapAndLeverage{value: 1 ether}(
            address(inputToken),
            1000e6,
            _emptySwap(),
            0,
            _dummyLeverageParams()
        );
        vm.stopPrank();
    }

    function test_swapAndLeverage_native_revertsOnMsgValueMismatch() external {
        vm.deal(alice, 2 ether);

        vm.prank(alice);
        vm.expectRevert(FLRError.FlashLeverageRouter__InvalidMsgValue.selector);
        flRouter.swapAndLeverage{value: 1 ether}(
            address(0),
            2 ether,
            _emptySwap(),
            0,
            _dummyLeverageParams()
        );
    }

    // ═══════════════════════════════════════════════
    //              REVERT CASES
    // ═══════════════════════════════════════════════

    function test_swapAndLeverage_revertsOnZeroAmountIn() external {
        vm.prank(alice);
        vm.expectRevert(
            FLRError.FlashLeverageRouter__AmountInCannotBeZero.selector
        );
        flRouter.swapAndLeverage(
            address(inputToken),
            0,
            _emptySwap(),
            0,
            _dummyLeverageParams()
        );
    }

    function test_swapAndLeverage_revertsOnInvalidPreSwapRouter() external {
        inputToken.mint(alice, 1000e6);

        vm.startPrank(alice);
        inputToken.approve(address(flRouter), 1000e6);

        vm.expectRevert(
            FLRError.FlashLeverageRouter__InvalidSwapRouter.selector
        );
        flRouter.swapAndLeverage(
            address(inputToken),
            1000e6,
            SwapData({extRouter: makeAddr("badRouter"), extCalldata: ""}),
            0,
            _dummyLeverageParams()
        );
        vm.stopPrank();
    }

    function test_swapAndLeverage_revertsOnUnsupportedMarket() external {
        uint256 inputAmount = 1000e6;
        uint256 collateralFromSwap = 10e18;

        (SwapData memory preSwap, ) = _buildFullSwapParams(
            inputAmount,
            collateralFromSwap
        );

        inputToken.mint(alice, inputAmount);

        vm.startPrank(alice);
        inputToken.approve(address(flRouter), inputAmount);

        vm.expectRevert();
        flRouter.swapAndLeverage(
            address(inputToken),
            inputAmount,
            preSwap,
            0,
            LeverageParams({
                marketId: keccak256("fake"),
                amountCollateral: collateralFromSwap,
                amountFlashLoan: 5e18,
                swapData: _emptySwap(),
                minTokenOut: 0
            })
        );
        vm.stopPrank();
    }

    function test_swapAndLeverage_revertsWhenRouterNotApprovedOperator()
        external
    {
        fl.setApprovedOperator(address(flRouter), false);

        uint256 inputAmount = 1000e6;
        uint256 collateralFromSwap = 10e18;

        (
            SwapData memory preSwap,
            LeverageParams memory params
        ) = _buildFullSwapParams(inputAmount, collateralFromSwap);

        inputToken.mint(alice, inputAmount);

        vm.startPrank(alice);
        inputToken.approve(address(flRouter), inputAmount);

        vm.expectRevert();
        flRouter.swapAndLeverage(
            address(inputToken),
            inputAmount,
            preSwap,
            0,
            params
        );
        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════
    //         REALLOCATE + SWAP + LEVERAGE
    // ═══════════════════════════════════════════════

    function test_reallocateSwapAndLeverage_erc20_withFees() external {
        uint256 inputAmount = 1000e6;
        uint256 collateralFromSwap = 10e18;
        uint256 reallocateFee = 0.01 ether;

        (
            SwapData memory preSwap,
            LeverageParams memory params
        ) = _buildFullSwapParams(inputAmount, collateralFromSwap);

        ReallocateParams[] memory reallocateParams = _buildSingleReallocate(
            reallocateFee
        );

        inputToken.mint(alice, inputAmount);
        vm.deal(alice, reallocateFee);

        vm.startPrank(alice);
        inputToken.approve(address(flRouter), inputAmount);
        flRouter.reallocateSwapAndLeverage{value: reallocateFee}(
            reallocateParams,
            address(inputToken),
            inputAmount,
            preSwap,
            0,
            params
        );
        vm.stopPrank();

        assertEq(fl.getUserLeveragePositions(alice).length, 1);
        assertEq(inputToken.balanceOf(address(flRouter)), 0);
        assertEq(address(flRouter).balance, 0);
    }

    function test_reallocateSwapAndLeverage_native_feesPlusSwap() external {
        uint256 ethAmount = 1 ether;
        uint256 collateralFromSwap = 10e18;
        uint256 reallocateFee = 0.01 ether;
        uint256 totalValue = ethAmount + reallocateFee;

        (
            SwapData memory preSwap,
            LeverageParams memory params
        ) = _buildNativeSwapParams(ethAmount, collateralFromSwap);

        ReallocateParams[] memory reallocateParams = _buildSingleReallocate(
            reallocateFee
        );

        vm.deal(alice, totalValue);

        vm.prank(alice);
        flRouter.reallocateSwapAndLeverage{value: totalValue}(
            reallocateParams,
            address(0),
            ethAmount,
            preSwap,
            0,
            params
        );

        assertEq(fl.getUserLeveragePositions(alice).length, 1);
        assertEq(address(flRouter).balance, 0);
    }

    function test_reallocateSwapAndLeverage_multipleFees() external {
        uint256 inputAmount = 1000e6;
        uint256 collateralFromSwap = 10e18;
        uint256 fee1 = 0.01 ether;
        uint256 fee2 = 0.02 ether;
        uint256 totalFees = fee1 + fee2;

        (
            SwapData memory preSwap,
            LeverageParams memory params
        ) = _buildFullSwapParams(inputAmount, collateralFromSwap);

        ReallocateParams[] memory reallocateParams = new ReallocateParams[](2);
        reallocateParams[0] = _buildReallocateParams(makeAddr("vault1"), fee1);
        reallocateParams[1] = _buildReallocateParams(makeAddr("vault2"), fee2);

        inputToken.mint(alice, inputAmount);
        vm.deal(alice, totalFees);

        vm.startPrank(alice);
        inputToken.approve(address(flRouter), inputAmount);
        flRouter.reallocateSwapAndLeverage{value: totalFees}(
            reallocateParams,
            address(inputToken),
            inputAmount,
            preSwap,
            0,
            params
        );
        vm.stopPrank();

        assertEq(fl.getUserLeveragePositions(alice).length, 1);
        assertEq(address(flRouter).balance, 0);
    }

    // ═══════════════════════════════════════════════
    //         REALLOCATE + LEVERAGE (no swap)
    // ═══════════════════════════════════════════════

    function test_reallocateAndLeverage_success() external {
        uint256 collateral = 10e18;
        uint256 reallocateFee = 0.01 ether;

        uint256 flashLoan = _calcFlashLoan(
            STANDARD_LTV,
            collateral,
            correlatedMarket
        );
        uint256 leverageSwapOut = _calcSwapOutput(flashLoan, correlatedMarket);
        SwapData memory leverageSwap = _buildSwapData(
            address(loanToken),
            address(collateralToken),
            flashLoan,
            leverageSwapOut
        );

        ReallocateParams[] memory reallocateParams = _buildSingleReallocate(
            reallocateFee
        );

        collateralToken.mint(alice, collateral);
        vm.deal(alice, reallocateFee);

        vm.startPrank(alice);
        collateralToken.approve(address(flRouter), collateral);
        flRouter.reallocateAndLeverage{value: reallocateFee}(
            reallocateParams,
            LeverageParams({
                marketId: correlatedMarketId,
                amountCollateral: collateral,
                amountFlashLoan: flashLoan,
                swapData: leverageSwap,
                minTokenOut: 0
            })
        );
        vm.stopPrank();

        assertEq(fl.getUserLeveragePositions(alice).length, 1);
        assertEq(collateralToken.balanceOf(address(flRouter)), 0);
        assertEq(address(flRouter).balance, 0);
    }

    // ═══════════════════════════════════════════════
    //         REALLOCATE EDGE CASES
    // ═══════════════════════════════════════════════

    function test_reallocateSwapAndLeverage_skipsEmptyWithdrawals() external {
        uint256 inputAmount = 1000e6;
        uint256 collateralFromSwap = 10e18;

        (
            SwapData memory preSwap,
            LeverageParams memory params
        ) = _buildFullSwapParams(inputAmount, collateralFromSwap);

        ReallocateParams[] memory reallocateParams = new ReallocateParams[](1);
        reallocateParams[0] = ReallocateParams({
            vault: makeAddr("vault"),
            fee: 0,
            withdrawals: new Withdrawal[](0),
            supplyMarketParams: _toSupplyMarketParams(correlatedMarket)
        });

        inputToken.mint(alice, inputAmount);

        vm.startPrank(alice);
        inputToken.approve(address(flRouter), inputAmount);
        flRouter.reallocateSwapAndLeverage(
            reallocateParams,
            address(inputToken),
            inputAmount,
            preSwap,
            0,
            params
        );
        vm.stopPrank();

        assertEq(fl.getUserLeveragePositions(alice).length, 1);
    }

    function test_reallocateAndLeverage_refundsExcessFees() external {
        uint256 collateral = 10e18;
        uint256 reallocateFee = 0.01 ether;
        uint256 extraEth = 0.05 ether;

        uint256 flashLoan = _calcFlashLoan(
            STANDARD_LTV,
            collateral,
            correlatedMarket
        );
        uint256 leverageSwapOut = _calcSwapOutput(flashLoan, correlatedMarket);
        SwapData memory leverageSwap = _buildSwapData(
            address(loanToken),
            address(collateralToken),
            flashLoan,
            leverageSwapOut
        );

        ReallocateParams[] memory reallocateParams = _buildSingleReallocate(
            reallocateFee
        );

        collateralToken.mint(alice, collateral);
        vm.deal(alice, reallocateFee + extraEth);

        vm.startPrank(alice);
        collateralToken.approve(address(flRouter), collateral);
        flRouter.reallocateAndLeverage{value: reallocateFee + extraEth}(
            reallocateParams,
            LeverageParams({
                marketId: correlatedMarketId,
                amountCollateral: collateral,
                amountFlashLoan: flashLoan,
                swapData: leverageSwap,
                minTokenOut: 0
            })
        );
        vm.stopPrank();

        assertEq(fl.getUserLeveragePositions(alice).length, 1);
        assertEq(alice.balance, extraEth, "Excess ETH should be refunded");
        assertEq(address(flRouter).balance, 0);
    }

    // ─── Internal helpers ───

    function _emptySwap() internal view returns (SwapData memory) {
        return SwapData({extRouter: address(router), extCalldata: ""});
    }

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

    function _buildFullSwapParams(
        uint256 inputAmount,
        uint256 collateralFromSwap
    ) internal returns (SwapData memory preSwap, LeverageParams memory params) {
        collateralToken.mint(address(router), collateralFromSwap);
        preSwap = SwapData({
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

        params = LeverageParams({
            marketId: correlatedMarketId,
            amountCollateral: collateralFromSwap,
            amountFlashLoan: flashLoan,
            swapData: leverageSwap,
            minTokenOut: 0
        });
    }

    function _buildNativeSwapParams(
        uint256 ethAmount,
        uint256 collateralFromSwap
    ) internal returns (SwapData memory preSwap, LeverageParams memory params) {
        collateralToken.mint(address(router), collateralFromSwap);
        preSwap = SwapData({
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

        params = LeverageParams({
            marketId: correlatedMarketId,
            amountCollateral: collateralFromSwap,
            amountFlashLoan: flashLoan,
            swapData: leverageSwap,
            minTokenOut: 0
        });
    }

    function _toSupplyMarketParams(
        MarketParams memory m
    ) internal pure returns (SupplyMarketParams memory) {
        return
            SupplyMarketParams({
                loanToken: m.loanToken,
                collateralToken: m.collateralToken,
                oracle: m.oracle,
                irm: m.irm,
                lltv: m.lltv
            });
    }

    function _buildReallocateParams(
        address vault,
        uint256 fee
    ) internal view returns (ReallocateParams memory) {
        Withdrawal[] memory withdrawals = new Withdrawal[](1);
        withdrawals[0] = Withdrawal({
            marketParams: _toSupplyMarketParams(correlatedMarket),
            amount: 1e18
        });

        return
            ReallocateParams({
                vault: vault,
                fee: fee,
                withdrawals: withdrawals,
                supplyMarketParams: _toSupplyMarketParams(correlatedMarket)
            });
    }

    function _buildSingleReallocate(
        uint256 fee
    ) internal returns (ReallocateParams[] memory) {
        ReallocateParams[] memory params = new ReallocateParams[](1);
        params[0] = _buildReallocateParams(makeAddr("vault"), fee);
        return params;
    }
}
