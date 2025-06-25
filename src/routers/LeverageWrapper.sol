// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import {IFlashLeverage} from "../interfaces/IFlashLeverage.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {TokenHelper} from "../core/libraries/TokenHelper.sol";
import {Errors} from "../core/libraries/Errors.sol";
import {ICurveCryptoSwap} from "../interfaces/ICurveCryptoSwap.sol";

/**
 * @title Leverage Wrapper
 * @notice This contract is used when a user wants to take leverage on a collateral token
 * using a token of their choice. It automatically swaps the supported fromToken to the required
 * collateral token and opens a leveraged position on it via the FlashLeverage contract.
 */

contract LeverageWrapper is Ownable2Step, TokenHelper {
    IFlashLeverage private immutable i_flashLeverage;

    // supportedToken => collateralToken => curve pool
    mapping(address => mapping(address collateralToken => address curvePool)) s_tokenCurvePools;

    constructor(address flashLeverage) Ownable(msg.sender) {
        i_flashLeverage = IFlashLeverage(flashLeverage);
    }

    /////////////////////////
    // Modifiers

    function leverage(
        address fromToken,
        uint256 amountToken,
        address collateralToken,
        uint256 desiredLtv
    ) external {
        _transferIn(fromToken, msg.sender, amountToken);

        ICurveCryptoSwap tokenCurvePool = ICurveCryptoSwap(
            s_tokenCurvePools[fromToken][collateralToken]
        );

        _safeApprove(fromToken, address(tokenCurvePool), amountToken);
        uint256 amountSwappedCollateral = tokenCurvePool.exchange(
            1,
            0,
            amountToken,
            0,
            address(this)
        );

        _safeApprove(
            collateralToken,
            address(i_flashLeverage),
            amountSwappedCollateral
        );
        i_flashLeverage.leverage(
            msg.sender,
            collateralToken,
            amountSwappedCollateral,
            desiredLtv
        );
    }

    function addSupportedToken(
        address fromToken,
        address[] memory collateralTokens,
        address[] memory curvePools
    ) external onlyOwner {
        require(
            collateralTokens.length == curvePools.length,
            "Length Mismatch"
        );

        for (uint256 i = 0; i < collateralTokens.length; i++) {
            require(
                collateralTokens[i] != address(0),
                Errors.PositionManager__InvalidTokenAddress()
            );
            s_tokenCurvePools[fromToken][collateralTokens[i]] = curvePools[i];
        }
    }
}
