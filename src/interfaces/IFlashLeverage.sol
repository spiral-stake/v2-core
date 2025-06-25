// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import {IERC3156FlashBorrower} from "@openzeppelin/contracts/interfaces/IERC3156FlashBorrower.sol";
import {LeveragePosition} from "../core/structs/LeveragePosition.sol";

interface IFlashLeverage is IERC3156FlashBorrower {
    // Struct getter
    function getUserLeveragePositions(
        address user
    ) external view returns (LeveragePosition[] memory);

    // Primary actions
    function leverage(
        address owner,
        address collateralToken,
        uint256 userCollateralAmount,
        uint256 desiredLtv
    ) external;

    function unleverage(uint256 leveragePositionId) external;

    // Admin
    function addSupportedCollateralTokens(
        address[] memory collateralTokens,
        address[] memory curvePools
    ) external;

    // Constants
    function MAX_LEVERAGE_LTV() external view returns (uint256);
}
