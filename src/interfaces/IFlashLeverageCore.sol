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
        CollateralTokenConfig[] calldata tokensConfig
    ) external;

    function setManager(address manager, bool value) external;

    function renounceOwnership() external;

    // ======== Public / External View Functions ========

    function calcLeverageFlashLoan(
        address collateralToken,
        address loanToken,
        uint256 amountCollateral
    ) external view returns (uint256);

    function calcUnleverageFlashLoan(
        address collateralToken,
        address loanToken,
        uint256 sharesToBurn
    ) external view returns (uint256);

    function getCollateralValueInLoanToken(
        address collateralToken,
        address loanToken,
        uint256 amountCollateral
    ) external view returns (uint256);

    function getSharesValueInLoanToken(
        address collateralToken,
        address loanToken,
        uint256 sharesBorrowed
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

    function i_morpho() external view returns (address);

    function i_pendleRouter() external view returns (address);

    function i_liquidationBuffer() external view returns (uint256);

    function i_slippageBuffer() external view returns (uint256);
}
