// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import {IMorpho, MarketParams, Id} from "@morpho/interfaces/IMorpho.sol";
import {Withdrawal, IPublicAllocator, MarketParams as SupplyMarketParams} from "@morpho-public-allocator/interfaces/IPublicAllocator.sol";
import {LeverageParams} from "../core/structs/LeverageParams.sol";
import {SwapData} from "../core/structs/SwapData.sol";
import {TokenHelper} from "../core/libraries/TokenHelper.sol";

library FLRError {
    error FlashLeverageRouter__ZeroAddress();
    error FlashLeverageRouter__AmountInCannotBeZero();
    error FlashLeverageRouter__InvalidSwapRouter();
    error FlashLeverageRouter__SwapRouterCallFailed();
    error FlashLeverageRouter__MinTokenOutNotMet();
    error FlashLeverageRouter__InvalidMsgValue();
    error FlashLeverageRouter__ReallocateFailed();
}

interface IFlashLeverage {
    function leverage(
        address onBehalfOf,
        LeverageParams calldata leverageParams
    ) external;

    function supplyCollateral(
        address user,
        uint256 positionId,
        uint256 amountCollateral
    ) external;

    function repay(
        address user,
        uint256 positionId,
        uint256 amountRepay,
        uint256 borrowShares
    ) external;

    function isValidSwapRouter(address router) external returns (bool);
}

struct ReallocateParams {
    address vault;
    uint256 fee;
    Withdrawal[] withdrawals;
    SupplyMarketParams supplyMarketParams;
}

contract FlashLeverageRouter is TokenHelper {
    IMorpho public immutable i_morpho;
    IFlashLeverage public immutable i_flashLeverage;
    IPublicAllocator public immutable i_publicAllocator;

    constructor(
        address morphoAddress,
        address publicAllocatorAddress,
        address flashLeverageAddress
    ) {
        require(
            morphoAddress != address(0) &&
                flashLeverageAddress != address(0) &&
                publicAllocatorAddress != address(0),
            FLRError.FlashLeverageRouter__ZeroAddress()
        );
        i_flashLeverage = IFlashLeverage(flashLeverageAddress);
        i_morpho = IMorpho(morphoAddress);
        i_publicAllocator = IPublicAllocator(publicAllocatorAddress);
    }

    function swapAndLeverage(
        address tokenIn,
        uint256 amountIn,
        SwapData calldata swapData,
        uint256 minTokenOut,
        LeverageParams memory leverageParams
    ) external payable {
        _swapAndLeverage(
            msg.sender,
            tokenIn,
            amountIn,
            swapData,
            minTokenOut,
            leverageParams,
            0 // no reallocation fees
        );
    }

    function reallocateAndLeverage(
        ReallocateParams[] memory reallocateParams,
        LeverageParams memory leverageParams
    ) external payable {
        address user = msg.sender;

        _reallocate(reallocateParams);

        MarketParams memory market = i_morpho.idToMarketParams(
            Id.wrap(leverageParams.marketId)
        );

        _transferIn(
            market.collateralToken,
            user,
            leverageParams.amountCollateral
        );

        _forceApprove(
            market.collateralToken,
            address(i_flashLeverage),
            leverageParams.amountCollateral
        );

        i_flashLeverage.leverage(user, leverageParams);

        // Refund unconsumed fees
        _transferOut(NATIVE, user, _selfBalance(NATIVE));
    }

    function reallocateSwapAndLeverage(
        ReallocateParams[] memory reallocateParams,
        address tokenIn,
        uint256 amountIn,
        SwapData calldata swapData,
        uint256 minTokenOut,
        LeverageParams memory leverageParams
    ) external payable {
        uint256 totalFees = _reallocate(reallocateParams);

        _swapAndLeverage(
            msg.sender,
            tokenIn,
            amountIn,
            swapData,
            minTokenOut,
            leverageParams,
            totalFees
        );
    }

    function swapAndSupplyCollateral(
        address user,
        uint256 positionId,
        bytes32 marketId,
        address tokenIn,
        uint256 amountIn,
        SwapData calldata swapData,
        uint256 minTokenOut
    ) external payable {
        _swap(msg.sender, tokenIn, amountIn, swapData, 0);

        MarketParams memory market = i_morpho.idToMarketParams(
            Id.wrap(marketId)
        );

        uint256 amountCollateral = _selfBalance(market.collateralToken);
        require(
            amountCollateral >= minTokenOut,
            FLRError.FlashLeverageRouter__MinTokenOutNotMet()
        );

        _forceApprove(
            market.collateralToken,
            address(i_flashLeverage),
            amountCollateral
        );
        i_flashLeverage.supplyCollateral(user, positionId, amountCollateral);

        // Refund unconsumed tokenIn and any leftover ETH
        _transferOut(tokenIn, msg.sender, _selfBalance(tokenIn));
        if (tokenIn != NATIVE) {
            _transferOut(NATIVE, msg.sender, _selfBalance(NATIVE));
        }
    }

    function swapAndRepay(
        address user,
        uint256 positionId,
        bytes32 marketId,
        address tokenIn,
        uint256 amountIn,
        SwapData calldata swapData,
        uint256 minTokenOut,
        uint256 borrowShares
    ) external payable {
        _swap(msg.sender, tokenIn, amountIn, swapData, 0);

        MarketParams memory market = i_morpho.idToMarketParams(
            Id.wrap(marketId)
        );

        uint256 amountRepay = _selfBalance(market.loanToken);
        require(
            amountRepay >= minTokenOut,
            FLRError.FlashLeverageRouter__MinTokenOutNotMet()
        );

        _forceApprove(market.loanToken, address(i_flashLeverage), amountRepay);
        i_flashLeverage.repay(user, positionId, amountRepay, borrowShares);

        // Refund excess loan token returned by repay (when swapped > debt) and any unconsumed tokenIn
        _transferOut(
            market.loanToken,
            msg.sender,
            _selfBalance(market.loanToken)
        );
        _transferOut(tokenIn, msg.sender, _selfBalance(tokenIn));
        if (tokenIn != NATIVE) {
            _transferOut(NATIVE, msg.sender, _selfBalance(NATIVE));
        }
    }

    // ─── Internal ───

    function _reallocate(
        ReallocateParams[] memory reallocateParams
    ) internal returns (uint256 totalFees) {
        for (uint256 i; i < reallocateParams.length; ++i) {
            ReallocateParams memory params = reallocateParams[i];

            if (params.withdrawals.length > 0) {
                i_publicAllocator.reallocateTo{value: params.fee}(
                    params.vault,
                    params.withdrawals,
                    params.supplyMarketParams
                );

                totalFees += params.fee;
            }
        }
    }

    function _swapAndLeverage(
        address user,
        address tokenIn,
        uint256 amountIn,
        SwapData calldata swapData,
        uint256 minTokenOut,
        LeverageParams memory leverageParams,
        uint256 reallocateFees
    ) internal {
        _swap(user, tokenIn, amountIn, swapData, reallocateFees);

        MarketParams memory market = i_morpho.idToMarketParams(
            Id.wrap(leverageParams.marketId)
        );

        leverageParams.amountCollateral = _selfBalance(market.collateralToken);
        require(
            leverageParams.amountCollateral >= minTokenOut,
            FLRError.FlashLeverageRouter__MinTokenOutNotMet()
        );

        _forceApprove(
            market.collateralToken,
            address(i_flashLeverage),
            leverageParams.amountCollateral
        );

        i_flashLeverage.leverage(user, leverageParams);

        // Refund unconsumed tokenIn and any leftover ETH
        _transferOut(tokenIn, user, _selfBalance(tokenIn));
        if (tokenIn != NATIVE) {
            _transferOut(NATIVE, user, _selfBalance(NATIVE));
        }
    }

    function _swap(
        address funder,
        address tokenIn,
        uint256 amountIn,
        SwapData calldata swapData,
        uint256 reallocateFees
    ) internal {
        require(
            amountIn > 0,
            FLRError.FlashLeverageRouter__AmountInCannotBeZero()
        );
        require(
            i_flashLeverage.isValidSwapRouter(swapData.extRouter),
            FLRError.FlashLeverageRouter__InvalidSwapRouter()
        );

        bool success;
        if (tokenIn == NATIVE) {
            // msg.value must cover both reallocation fees and swap amount
            require(
                msg.value == amountIn + reallocateFees,
                FLRError.FlashLeverageRouter__InvalidMsgValue()
            );
            (success, ) = swapData.extRouter.call{value: amountIn}(
                swapData.extCalldata
            );
        } else {
            require(
                msg.value == reallocateFees,
                FLRError.FlashLeverageRouter__InvalidMsgValue()
            );
            _transferIn(tokenIn, funder, amountIn);
            _forceApprove(tokenIn, address(swapData.extRouter), amountIn);
            (success, ) = swapData.extRouter.call(swapData.extCalldata);
        }
        require(success, FLRError.FlashLeverageRouter__SwapRouterCallFailed());
    }

    receive() external payable {}
}
