// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

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
    FlashLeverage public immutable i_flashLeverage;

    constructor(address flashLeverageAddress) {
        i_flashLeverage = FlashLeverage(flashLeverageAddress);
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

        leverageParams.amountCollateral = _selfBalance(
            leverageParams.collateralToken
        );
        _forceApprove(
            leverageParams.collateralToken,
            address(i_flashLeverage),
            leverageParams.amountCollateral
        );

        i_flashLeverage.leverage(onBehalfOf, leverageParams);
    }
}
