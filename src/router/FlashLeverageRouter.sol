// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import {IMorpho, MarketParams, Id} from "@morpho/interfaces/IMorpho.sol";
import {LeverageParams} from "../core/structs/LeverageParams.sol";
import {SwapData} from "../core/structs/SwapData.sol";
import {TokenHelper} from "../core/libraries/TokenHelper.sol";

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
            "Zero address"
        );
        i_flashLeverage = FlashLeverage(flashLeverageAddress);
        i_morpho = IMorpho(morphoAddress);
    }

    /**
     * @notice Swaps an input token to the market's collateral token, then opens a leveraged position.
     * @param onBehalfOf The address of the user for whom the position is being created.
     * @param leverageParams Leverage parameters. amountCollateral will be overwritten with swap output.
     * @param tokenIn The token to swap from.
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
        require(amountIn > 0, "AmountIn cannot be zero");
        require(onBehalfOf != address(0), "Invalid onBehalfOf");
        require(
            i_flashLeverage.isValidSwapRouter(swapData.extRouter),
            "Invalid Swap Router"
        );

        _transferIn(tokenIn, msg.sender, amountIn);

        _forceApprove(tokenIn, address(swapData.extRouter), amountIn);
        (bool success, ) = swapData.extRouter.call(swapData.extCalldata);
        require(success, "Swap Router Call Failed");

        MarketParams memory market = i_morpho.idToMarketParams(
            Id.wrap(leverageParams.marketId)
        );

        leverageParams.amountCollateral = _selfBalance(market.collateralToken);
        require(
            leverageParams.amountCollateral >= minTokenOut,
            "Slippage exceeded"
        );

        _forceApprove(
            market.collateralToken,
            address(i_flashLeverage),
            leverageParams.amountCollateral
        );

        i_flashLeverage.leverage(onBehalfOf, leverageParams);
    }
}
