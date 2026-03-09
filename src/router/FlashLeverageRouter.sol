// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import {IMorpho, MarketParams, Id} from "@morpho/interfaces/IMorpho.sol";
import {LeverageParams} from "../core/structs/LeverageParams.sol";
import {SwapData} from "../core/structs/SwapData.sol";
import {TokenHelper} from "../core/libraries/TokenHelper.sol";

library FLRError {
    error FlashLeverageRouter__ZeroAddress();
    error FlashLeverageRouter__AmountInCannotBeZero();
    error FlashLeverageRouter__InvalidOnBehalfOf();
    error FlashLeverageRouter__InvalidSwapRouter();
    error FlashLeverageRouter__SwapRouterCallFailed();
    error FlashLeverageRouter__MinTokenOutNotMet();
}

interface FlashLeverage {
    function leverage(
        address onBehalfOf,
        LeverageParams calldata leverageParams
    ) external;

    function isValidSwapRouter(address router) external returns (bool);
}

contract FlashLeverageRouter is TokenHelper {
    IMorpho public immutable i_morpho;
    FlashLeverage public immutable i_flashLeverage;

    constructor(address morphoAddress, address flashLeverageAddress) {
        require(
            morphoAddress != address(0) && flashLeverageAddress != address(0),
            FLRError.FlashLeverageRouter__ZeroAddress()
        );
        i_flashLeverage = FlashLeverage(flashLeverageAddress);
        i_morpho = IMorpho(morphoAddress);
    }

    /**
     * @notice Swaps an input token to the market's collateral token, then opens a leveraged position.
     * @param onBehalfOf The address of the user for whom the position is being created.
     * @param leverageParams Leverage parameters. amountCollateral will be overwritten with swap output.
     * @param tokenIn The token to swap from. address(0) for native token
     * @param amountIn The amount of tokenIn to swap.
     * @param swapData Swap configuration for the external router.
     * @param minTokenOut Minimum collateral tokens expected from the swap (slippage protection).
     */
    function swapAndLeverage(
        address onBehalfOf,
        LeverageParams memory leverageParams,
        address tokenIn,
        uint256 amountIn,
        SwapData calldata swapData,
        uint256 minTokenOut
    ) external {
        require(
            amountIn > 0,
            FLRError.FlashLeverageRouter__AmountInCannotBeZero()
        );
        require(
            onBehalfOf != address(0),
            FLRError.FlashLeverageRouter__InvalidOnBehalfOf()
        );
        require(
            i_flashLeverage.isValidSwapRouter(swapData.extRouter),
            FLRError.FlashLeverageRouter__InvalidSwapRouter()
        );

        bool success;
        if (tokenIn == NATIVE) {
            (success, ) = swapData.extRouter.call{value: amountIn}(
                swapData.extCalldata
            );
        } else {
            _transferIn(tokenIn, msg.sender, amountIn);
            _forceApprove(tokenIn, address(swapData.extRouter), amountIn);
            (success, ) = swapData.extRouter.call(swapData.extCalldata);
        }
        require(success, FLRError.FlashLeverageRouter__SwapRouterCallFailed());

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

        i_flashLeverage.leverage(onBehalfOf, leverageParams);

        // Refund unconsumed tokenIn to user, if any
        uint256 tokenInAfter = tokenIn == NATIVE
            ? address(this).balance
            : _selfBalance(tokenIn);

        if (tokenInAfter > 0) {
            if (tokenIn == NATIVE) {
                (bool sent, ) = msg.sender.call{value: tokenInAfter}("");
                require(sent);
            } else {
                _transferOut(tokenIn, msg.sender, tokenInAfter);
            }
        }
    }
}
