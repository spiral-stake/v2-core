// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import {LeverageParams, UnleverageParams} from "../core/structs/LeverageParams.sol";
import {CollateralTokenConfig} from "../core/structs/CollateralTokenConfig.sol";
import {CoreLeveragePosition} from "../core/structs/CoreLeveragePosition.sol";

interface IFlashLeverageCore {
    // ======== External Mutable Functions ========

    function leverage(LeverageParams calldata params) external;

    function unleverage(UnleverageParams calldata params) external;

    function addSupportedCollateralTokens(
        CollateralTokenConfig[] calldata configs
    ) external;

    function setManager(address manager, bool value) external;

    function renounceOwnership() external;

    // ======== Public / External View Functions ========

    function calcFlashLoanAmount(
        address collateralToken,
        address loanToken,
        uint256 amountCollateral
    ) external view returns (uint256);

    function getCollateralValueInLoanToken(
        address collateralToken,
        address loanToken,
        uint256 amountCollateral
    ) external view returns (uint256);

    function getSafeLtv(
        address collateralToken,
        address loanToken
    ) external view returns (uint256);

    function getMaxLtv(
        address collateralToken,
        address loanToken
    ) external view returns (uint256);

    function getLiqLtv(
        address collateralToken,
        address loanToken
    ) external view returns (uint256);

    function getCoreLeveragePosition(
        address manager,
        address collateralToken,
        address loanToken
    ) external view returns (CoreLeveragePosition memory);
}
