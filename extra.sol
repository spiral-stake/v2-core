    // function swapAndLeverage(
    //     address onBehalfOf,
    //     SwapParams calldata swapParams,
    //     LeverageParams calldata params
    // )
    //     external
    //     validateOnBehalfOf(onBehalfOf)
    //     validateDesiredLtv(
    //         params.desiredLtv,
    //         params.collateralToken,
    //         params.loanToken
    //     )
    //     validateCollateralToken(params.collateralToken, params.loanToken)
    //     validateAmount(params.amountCollateral)
    // {
    //     _transferIn(swapParams.tokenIn, msg.sender, swapParams.amountIn);
    //     _swap(swapParams.tokenIn, swapParams.amountIn, swapParams.swapData);
    //     _transferBackRemaining(
    //         params.collateralToken,
    //         _selfBalance(params.collateralToken),
    //         params.amountCollateral
    //     );

    //     _leverage(onBehalfOf, params);
    // }