// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

/// @title SwapAggregator Abstract Contract
/// @notice Provides Pendle PT/token swap helpers for leverage flows.
/// @dev Wraps Pendle V2 router calls using simplified TokenInput/Output interfaces.

import {IPAllActionV3} from "@pendle/core-v2/contracts/interfaces/IPAllActionV3.sol";
import {ApproxParams, TokenInput, TokenOutput, SwapData, LimitOrderData, SwapType, FillOrderParams} from "@pendle/core-v2/contracts/interfaces/IPAllActionV3.sol";
import {TokenHelper} from "../libraries/TokenHelper.sol";
import {CollateralTokenData} from "../structs/CollateralTokenData.sol";

abstract contract SwapAggregator is TokenHelper {
    /////////////////////////
    // Constants and Immutables

    IPAllActionV3 private immutable i_pendleRouter;

    /////////////////////////
    // Storage

    mapping(address collateralToken => CollateralTokenData)
        private s_collateralTokenData;

    /////////////////////////
    // Constructor

    /// @param pendleRouter Address of the Pendle router.
    constructor(address pendleRouter) {
        i_pendleRouter = IPAllActionV3(pendleRouter);
    }

    /**
     * @notice Swaps borrowed loan token to PT (collateral) via Pendle.
     * @param loanToken Token being swapped from (e.g., USDC).
     * @param collateralToken Token to be received (e.g., PT).
     * @param amountLoan Amount of loan token to swap.
     * @param approxParams Pendle slippage approximation settings.
     * @param pendleSwap Address used to route the swap.
     * @param swapData Swap path details.
     * @param limitOrderData Optional limit order info.
     * @return amountSwappedCollateralToken Amount of PT tokens received.
     */
    function _swapLoanTokenToCollateralToken(
        address loanToken,
        address collateralToken,
        uint256 amountLoan,
        ApproxParams memory approxParams,
        address pendleSwap,
        SwapData memory swapData,
        LimitOrderData memory limitOrderData
    ) internal returns (uint256 amountSwappedCollateralToken) {
        CollateralTokenData memory tokenData = s_collateralTokenData[
            collateralToken
        ];

        _forceApprove(loanToken, address(i_pendleRouter), amountLoan);
        (amountSwappedCollateralToken, , ) = i_pendleRouter.swapExactTokenForPt(
            address(this),
            tokenData.pendleMarket,
            0,
            approxParams,
            _createTokenInputSimple(
                loanToken,
                amountLoan,
                tokenData.underlyingToken,
                pendleSwap,
                swapData
            ),
            limitOrderData
        );
    }

    /**
     * @notice Swaps PT (collateral) back to loan token via Pendle.
     * @param collateralToken Token to be swapped from (PT).
     * @param loanToken Token to be received (e.g., USDC).
     * @param amountCollateral Amount of PT to swap.
     * @param pendleSwap Address used to route the swap.
     * @param swapData Swap path details.
     * @param limitOrderData Optional limit order info.
     * @return amountSwappedLoanToken Amount of loan tokens received.
     */
    function _swapCollateralTokenToLoanToken(
        address collateralToken,
        address loanToken,
        uint256 amountCollateral,
        address pendleSwap,
        SwapData memory swapData,
        LimitOrderData memory limitOrderData
    ) internal returns (uint256 amountSwappedLoanToken) {
        CollateralTokenData memory tokenData = s_collateralTokenData[
            collateralToken
        ];

        _safeApprove(
            collateralToken,
            address(i_pendleRouter),
            amountCollateral
        );
        (amountSwappedLoanToken, , ) = i_pendleRouter.swapExactPtForToken(
            address(this),
            tokenData.pendleMarket,
            amountCollateral,
            _createTokenOutputSimple(
                loanToken,
                0,
                tokenData.underlyingToken,
                pendleSwap,
                swapData
            ),
            limitOrderData
        );
    }

    /**
     * @notice Creates a TokenInput struct for token → PT swaps.
     * @param tokenIn Base token being swapped.
     * @param netTokenIn Amount of tokenIn to send.
     * @param tokenMintSy Token to mint PT from.
     * @param pendleSwap Swap router address.
     * @param swapData Swap route/configuration.
     * @return tokenInput Pendle-compatible token input.
     */
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

    /**
     * @notice Creates a TokenOutput struct for PT → token swaps.
     * @param tokenOut Desired output token.
     * @param minTokenOut Minimum acceptable output.
     * @param tokenRedeemSy Token to redeem PT into.
     * @param pendleSwap Swap router address.
     * @param swapData Swap route/configuration.
     * @return tokenOutput Pendle-compatible token output.
     */
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

    /**
     * @notice Returns an empty `LimitOrderData` struct.
     * @dev Can be used if not leveraging limit orders.
     */
    function _createEmptyLimitOrderData()
        internal
        pure
        returns (LimitOrderData memory)
    {}

    /**
     * @notice Returns default approximation parameters for slippage-tolerant swaps.
     * @dev Can be reused for most basic trades.
     */
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

    /**
     * @notice Sets swap configuration for a specific collateral token.
     * @param collateralToken Address of the collateral token (e.g., PT).
     * @param tokenData Struct containing Pendle market and underlying token info.
     */
    function _updateCollateralTokenData(
        address collateralToken,
        CollateralTokenData memory tokenData
    ) internal {
        s_collateralTokenData[collateralToken] = tokenData;
    }
}
