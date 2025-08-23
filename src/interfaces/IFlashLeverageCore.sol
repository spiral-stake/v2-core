// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import {LeverageParams, UnleverageParams} from "../core/structs/LeverageParams.sol";
import {CoreLeveragePosition} from "../core/structs/CoreLeveragePosition.sol";

/**
 * @title IFlashLeverageCore
 * @dev This Interface only includes the functions required by FlashLeverage contract
 */

interface IFlashLeverageCore {
    function leverage(
        address onBehalfOf,
        LeverageParams calldata params
    ) external;

    function unleverage(
        address onBehalfOf,
        UnleverageParams calldata params
    ) external;

    function getUserCoreLeveragePosition(
        address user,
        uint256 desiredLtv,
        address collateralToken,
        address loanToken
    ) external view returns (CoreLeveragePosition memory);

    function getCollateralValueInLoanToken(
        address collateralToken,
        address loanToken,
        uint256 amountCollateral
    ) external view returns (uint256);
}
