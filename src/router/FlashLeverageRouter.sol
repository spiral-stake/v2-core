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
}

contract FlashLeverageRouter is TokenHelper {
    IMorpho public immutable i_morpho;
    FlashLeverage public immutable i_flashLeverage;

    constructor(address morphoAddress, address flashLeverageAddress) {
        i_flashLeverage = FlashLeverage(flashLeverageAddress);
        i_morpho = IMorpho(morphoAddress);
    }

    function swapAndLeverage(
        address onBehalfOf,
        LeverageParams memory leverageParams,
        address tokenIn,
        uint256 amountIn,
        SwapData calldata swapData
    ) external {
        require(amountIn > 0, "AmountIn cannot be zero");
        _transferIn(tokenIn, msg.sender, amountIn);

        _forceApprove(tokenIn, address(swapData.extRouter), amountIn);
        (bool success, ) = swapData.extRouter.call(swapData.extCalldata);
        require(success, "Swap Router Call Failed");

        MarketParams memory market = i_morpho.idToMarketParams(
            Id.wrap(leverageParams.marketId)
        );

        leverageParams.amountCollateral = _selfBalance(market.collateralToken);
        _forceApprove(
            market.collateralToken,
            address(i_flashLeverage),
            leverageParams.amountCollateral
        );

        i_flashLeverage.leverage(onBehalfOf, leverageParams);
    }
}
