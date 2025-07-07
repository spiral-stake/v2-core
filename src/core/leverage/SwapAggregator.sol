// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import {IPAllActionV3} from "@pendle/core-v2/contracts/interfaces/IPAllActionV3.sol";
import {IPMarket} from "@pendle/core-v2/contracts/interfaces/IPMarket.sol";
import {ApproxParams, TokenInput, TokenOutput, SwapData, LimitOrderData, SwapType, FillOrderParams} from "@pendle/core-v2/contracts/interfaces/IPAllActionV3.sol";
import {TokenHelper} from "../libraries/TokenHelper.sol";
import {SwapParams} from "../structs/SwapParams.sol";

abstract contract SwapAggregator is TokenHelper {
    IPAllActionV3 private immutable i_pendleRouter;
    mapping(address collateralToken => SwapParams) private s_swapParams;

    constructor(address pendleRouter) {
        i_pendleRouter = IPAllActionV3(pendleRouter);
    }

    function _swapLoanTokenToCollateralToken(
        address loanToken,
        address collateralToken,
        uint256 amountLoan,
        address pendleSwap,
        SwapData memory swapData,
        ApproxParams memory approxParams
    ) internal returns (uint256 amountSwappedCollateralToken) {
        SwapParams memory swapParams = s_swapParams[collateralToken];

        _forceApprove(loanToken, address(i_pendleRouter), amountLoan);
        (amountSwappedCollateralToken, , ) = i_pendleRouter.swapExactTokenForPt(
            address(this),
            swapParams.pendleMarket,
            0,
            approxParams,
            _createTokenInputSimple(
                loanToken,
                amountLoan,
                swapParams.underlyingToken,
                pendleSwap,
                swapData
            ),
            _createEmptyLimitOrderData()
        );
    }

    function _swapCollateralTokenToLoanToken(
        address collateralToken,
        address loanToken,
        uint256 amountCollateral,
        address pendleSwap,
        SwapData memory swapData,
        LimitOrderData memory limitOrderData
    ) internal returns (uint256 amountSwappedLoanToken) {
        SwapParams memory swapParams = s_swapParams[collateralToken];

        _safeApprove(
            collateralToken,
            address(i_pendleRouter),
            amountCollateral
        );
        (amountSwappedLoanToken, , ) = i_pendleRouter.swapExactPtForToken(
            address(this),
            swapParams.pendleMarket,
            amountCollateral,
            _createTokenOutputSimple(
                loanToken,
                0,
                swapParams.underlyingToken,
                pendleSwap,
                swapData
            ),
            limitOrderData
        );
    }

    /// @dev Creates a TokenInput struct without using any swap aggregator
    /// @param tokenIn must be one of the SY's tokens in (obtain via `IStandardizedYield#getTokensIn`)
    /// @param netTokenIn amount of token in
    function _createTokenInputSimple(
        address tokenIn,
        uint256 netTokenIn,
        address tokenMintSy,
        address pendleSwap,
        SwapData memory swapData
    ) internal pure returns (TokenInput memory) {
        return
            TokenInput({
                tokenIn: tokenIn,
                netTokenIn: netTokenIn,
                tokenMintSy: tokenMintSy,
                pendleSwap: pendleSwap,
                swapData: swapData
            });
    }

    /// @dev Creates a TokenOutput struct without using any swap aggregator
    /// @param tokenOut must be one of the SY's tokens out (obtain via `IStandardizedYield#getTokensOut`)
    /// @param minTokenOut minimum amount of token out
    function _createTokenOutputSimple(
        address tokenOut,
        uint256 minTokenOut,
        address tokenRedeemSy,
        address pendleSwap,
        SwapData memory swapData
    ) internal pure returns (TokenOutput memory) {
        return
            TokenOutput({
                tokenOut: tokenOut,
                minTokenOut: minTokenOut,
                tokenRedeemSy: tokenRedeemSy,
                pendleSwap: pendleSwap,
                swapData: swapData
            });
    }

    function _createEmptyLimitOrderData()
        internal
        pure
        returns (LimitOrderData memory)
    {}

    /// @dev Creates default ApproxParams for on-chain approximation
    function _createDefaultApproxParams()
        internal
        pure
        returns (ApproxParams memory)
    {
        return
            ApproxParams({
                guessMin: 0,
                guessMax: type(uint256).max,
                guessOffchain: 0,
                maxIteration: 256,
                eps: 1e14
            });
    }

    function _createSwapTypeNoAggregator()
        internal
        pure
        returns (SwapData memory)
    {}

    function _updateSwapParams(
        address collateralToken,
        SwapParams memory swapParams
    ) internal {
        s_swapParams[collateralToken] = swapParams;
    }
}
