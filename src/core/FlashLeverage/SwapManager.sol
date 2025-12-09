// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

/**
 * @title SwapAggregator
 * @notice SwapAggregator is the contract that facilatates the token swaps via aggregator(s)
 * @dev Currently only using kyberswap
 */

import {IPAllActionV3, ApproxParams, TokenInput, TokenOutput, SwapData, LimitOrderData} from "@pendle/core-v2/contracts/interfaces/IPAllActionV3.sol";
import {IPendleMarket} from "../../interfaces/IPendleMarket.sol";
import {TokenHelper} from "../libraries/TokenHelper.sol";

contract SwapManager is TokenHelper {
    /////////////////////////
    // Storage

    IPAllActionV3 public s_pendleRouter;

    mapping(address collateralToken => address pendleMarket)
        public s_pendleMarket;

    // List of router contracts from swap aggregators like kyberswap, odos... for swapping of non-PTs
    mapping(address => bool) public s_isSwapRouter;

    constructor(address pendleRouter, address[] memory routers) {
        s_pendleRouter = IPAllActionV3(pendleRouter);

        for (uint256 i; i < routers.length; i++) {
            s_isSwapRouter[routers[i]] = true;
        }
    }

    function _swapTokenToToken(
        address tokenIn, // For approval
        uint256 amountIn, // For approval
        SwapData memory swapData
    ) internal returns (uint256 returnAmount) {
        require(s_isSwapRouter[swapData.extRouter], "Unsupported Swap Router");

        _forceApprove(tokenIn, address(swapData.extRouter), amountIn);
        (bool success, bytes memory result) = swapData.extRouter.call(
            swapData.extCalldata
        );

        require(success, "Swap router call failed");
        (returnAmount, ) = abi.decode(result, (uint256, uint256));
    }

    /**
     * @notice Swaps borrowed loan token to PT (collateral) via Pendle.
     * @param tokenIn Token being swapped from (e.g., USDC).
     * @param PT Token to be received (e.g., PT).
     * @param amountIn Amount of loan token to swap.
     * @param approxParams Pendle slippage approximation settings.
     * @param pendleSwap Address used to route the swap.
     * @param swapData Swap path details.
     * @param limitOrderData Optional limit order info.
     * @return amountPtOut Amount of PT tokens received.
     */
    function _swapTokenToPt(
        address tokenIn,
        address PT,
        uint256 amountIn,
        SwapData memory swapData,
        uint256 minPtOut,
        ApproxParams memory approxParams,
        address pendleSwap,
        address tokenMintSy,
        LimitOrderData memory limitOrderData
    ) internal returns (uint256 amountPtOut) {
        _forceApprove(tokenIn, address(s_pendleRouter), amountIn);
        (amountPtOut, , ) = s_pendleRouter.swapExactTokenForPt(
            address(this),
            s_pendleMarket[PT],
            minPtOut,
            approxParams,
            TokenInput({
                tokenIn: tokenIn,
                netTokenIn: amountIn,
                tokenMintSy: tokenMintSy,
                pendleSwap: pendleSwap,
                swapData: swapData
            }),
            limitOrderData
        );
    }

    /**
     * @notice Swaps PT (collateral) back to loan token via Pendle.
     * @param PT Token to be swapped from (PT).
     * @param tokenOut Token to be received (e.g., USDC).
     * @param amountPt Amount of PT to swap.
     * @param pendleSwap Address used to route the swap.
     * @param swapData Swap path details.
     * @param limitOrderData Optional limit order info.
     * @return amountTokenOut Amount of output tokens received.
     */
    function _swapPtToToken(
        address PT,
        address tokenOut,
        uint256 amountPt,
        SwapData memory swapData,
        uint256 minTokenOut,
        address pendleSwap,
        address tokenRedeemSy,
        LimitOrderData memory limitOrderData
    ) internal returns (uint256 amountTokenOut) {
        _safeApprove(PT, address(s_pendleRouter), amountPt);

        IPendleMarket pendleMarket = IPendleMarket(s_pendleMarket[PT]);

        if (!pendleMarket.isExpired()) {
            (amountTokenOut, , ) = s_pendleRouter.swapExactPtForToken(
                address(this),
                s_pendleMarket[PT],
                amountPt,
                TokenOutput({
                    tokenOut: tokenOut,
                    minTokenOut: minTokenOut,
                    tokenRedeemSy: tokenRedeemSy,
                    pendleSwap: pendleSwap,
                    swapData: swapData
                }),
                limitOrderData
            );
        } else {
            (, , address YT) = pendleMarket.readTokens();

            (amountTokenOut, ) = s_pendleRouter.redeemPyToToken(
                address(this),
                YT,
                amountPt,
                TokenOutput({
                    tokenOut: tokenOut,
                    minTokenOut: minTokenOut,
                    tokenRedeemSy: tokenRedeemSy,
                    pendleSwap: pendleSwap,
                    swapData: swapData
                })
            );
        }
    }

    /**
     * @notice Sets swap configuration for a specific collateral token.
     * @param PT Address of the collateral token (e.g., PT).
     * @param pendleMarket Address of the pendle market for PT PT
     */
    function _updatePendleMarket(address PT, address pendleMarket) internal {
        s_pendleMarket[PT] = pendleMarket;
    }

    function _updatePendleRouter(address pendleRouter) internal {
        s_pendleRouter = IPAllActionV3(pendleRouter);
    }

    function _addSwapRouter(address router) internal {
        s_isSwapRouter[router] = true;
    }
}
