// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import {LeverageParams, UnleverageParams} from "../core/structs/LeverageParams.sol";
import {CollateralTokenConfig} from "../core/structs/CollateralTokenConfig.sol";
import {CoreLeveragePosition} from "../core/structs/CoreLeveragePosition.sol";

interface IFlashLeverageCore {
    // ======== External Mutable Functions ========

    function leverage(
        address onBehalfOf,
        LeverageParams calldata params
    ) external;

    function unleverage(
        address onBehalfOf,
        UnleverageParams calldata params
    ) external;

    function addSupportedCollateralTokens(
        CollateralTokenConfig[] calldata tokensConfig
    ) external;

    function onMorphoFlashLoan(
        uint256 amountLoan,
        bytes calldata data
    ) external;

    function owner() external returns (address);

    function addManager(address manager) external;

    function renounceOwnership() external;

    function getOrCreateUserProxy(
        address user,
        uint256 desiredLtv
    ) external returns (address proxy);

    // ======== Public / External View Functions ========

    function isManager(address manager) external view returns (bool);

    function calcLeverageFlashLoan(
        uint256 desiredLtv,
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

    function getLiqLtv(
        address collateralToken,
        address loanToken
    ) external view returns (uint256);

    function getMaxLtv(
        address collateralToken,
        address loanToken
    ) external view returns (uint256);

    function getUserCoreLeveragePosition(
        address user,
        uint256 desiredLtv,
        address collateralToken,
        address loanToken
    ) external view returns (CoreLeveragePosition memory);

    function getUserProxy(
        address user,
        uint256 desiredLtv
    ) external view returns (address);

    function i_morpho() external view returns (address);

    function i_pendleRouter() external view returns (address);

    function i_liquidationBuffer() external view returns (uint256);

    function i_slippageBuffer() external view returns (uint256);

    function i_userProxyImplementation() external view returns (address);
}
