// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

/**
 * @title SwapAggregator
 * @notice SwapAggregator is the contract that facilatates the token swaps via aggregator(s)
 * @dev Currently only using kyberswap
 */

import {TokenHelper} from "../libraries/TokenHelper.sol";
import {IPAllActionV3} from "@pendle/core-v2/contracts/interfaces/IPAllActionV3.sol";
import {ApproxParams, TokenInput, TokenOutput, SwapData, LimitOrderData, SwapType, FillOrderParams} from "@pendle/core-v2/contracts/interfaces/IPAllActionV3.sol";
import {TokenHelper} from "../libraries/TokenHelper.sol";
import {IPendleMarket} from "../../interfaces/IPendleMarket.sol";

contract SwapManager is TokenHelper {
    /////////////////////////
    // Constants and Immutables

    IPAllActionV3 public immutable i_pendleRouter;

    /////////////////////////
    // Storage

    mapping(address collateralToken => address pendleMarket)
        public s_pendleMarket;

    // List of router contracts from swap aggregators like kyberswap, odos... for swapping of non-PTs
    mapping(address => bool) public s_isRouter;

    constructor(address pendleRouter, address[] memory routers) {
        i_pendleRouter = IPAllActionV3(pendleRouter);

        for (uint256 i; i < routers.length; i++) {
            s_isRouter[routers[i]] = true;
        }
    }

    function _swapTokenToToken(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        SwapData memory swapData,
        uint256 minTokenOut
    ) internal returns (uint256 returnAmount) {
        require(s_isRouter[swapData.extRouter], "Unsupported Swap Router");

        _forceApprove(tokenIn, address(swapData.extRouter), amountIn);
        (bool success, bytes memory result) = swapData.extRouter.call(
            swapData.extCalldata
        );
        require(success, "Swap router call failed");

        (returnAmount, ) = abi.decode(result, (uint256, uint256));
        require(
            _selfBalance(tokenOut) >= minTokenOut && // This is not neccessary
                returnAmount >= minTokenOut,
            "Slippage: output amount too low"
        );
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
        _forceApprove(tokenIn, address(i_pendleRouter), amountIn);
        (amountPtOut, , ) = i_pendleRouter.swapExactTokenForPt(
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
        _safeApprove(PT, address(i_pendleRouter), amountPt);

        IPendleMarket pendleMarket = IPendleMarket(s_pendleMarket[PT]);

        if (!pendleMarket.isExpired()) {
            (amountTokenOut, , ) = i_pendleRouter.swapExactPtForToken(
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

            (amountTokenOut, ) = i_pendleRouter.redeemPyToToken(
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

    // function addRouter(address router) external onlyOwner {}
}
