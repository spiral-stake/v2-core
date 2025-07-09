// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import {LeverageParams, SwapData, ApproxParams, LimitOrderData} from "../core/structs/LeverageParams.sol";
import {LeveragePosition} from "../core/structs/LeveragePosition.sol";
import {CollateralTokenConfig} from "../core/structs/CollateralTokenConfig.sol";

interface IFlashLeverage {
    // ======== External Mutable Functions ========

    function leverage(
        address onBehalfOf,
        LeverageParams memory params
    ) external;

    function unleverage(
        uint256 positionId,
        address pendleSwap,
        SwapData memory swapData,
        LimitOrderData memory limitOrderData
    ) external;

    function addSupportedCollateralTokens(
        CollateralTokenConfig[] memory configs
    ) external;

    function setAmountUserCollateralCap(
        uint256 newAmountUserCollateralCap
    ) external;

    // ======== Public / External View Functions ========

    function calcLoanAmount(
        address collateralToken,
        address loanToken,
        uint256 userCollateralAmount
    ) external view returns (uint256);

    function getTokenUsdValue(
        address token,
        uint256 amount
    ) external view returns (uint256);

    function getMaxLtv(
        address collateralToken,
        address loanToken
    ) external view returns (uint256);

    function getUserLeveragePositions(
        address user
    ) external view returns (LeveragePosition[] memory);

    function getUserLeveragePosition(
        address user,
        uint256 positionId
    ) external view returns (LeveragePosition memory);

    function getAmountUserCollateralCap() external view returns (uint256);

    // ======== Readable Constants ========

    function LIQUIDATION_BUFFER() external pure returns (uint256);
}
