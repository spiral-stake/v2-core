// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import {IERC3156FlashLender} from "@openzeppelin/contracts/interfaces/IERC3156FlashLender.sol";
import {IERC3156FlashBorrower} from "@openzeppelin/contracts/interfaces/IERC3156FlashBorrower.sol";
import {Position} from "../core/structs/Position.sol";

/**
 * @title IPositionManager
 * @notice Interface for the PositionManager contract.
 */
interface IPositionManager is IERC3156FlashLender {
    // --- Core Position Functions ---

    function openPosition(
        address collateralToken,
        uint256 amountCollateral,
        uint256 amountToMint
    ) external returns (uint256 positionId);

    function depositCollateralAndMintStblUSD(
        uint256 positionId,
        uint256 amountCollateral,
        uint256 amountToMint
    ) external;

    function depositCollateral(
        uint256 positionId,
        uint256 amountCollateral
    ) external;

    function mintStblUSD(uint256 positionId, uint256 amountToMint) external;

    function redeemCollateralAndBurnStblUSD(
        uint256 positionId,
        uint256 amountCollateral,
        uint256 amountToBurn
    ) external;

    function redeemCollateral(
        uint256 positionId,
        uint256 amountCollateral
    ) external;

    function burnStblUSD(uint256 positionId, uint256 amountToBurn) external;

    function liquidate(uint256 positionId) external;

    function addSupportedCollateralTokens(
        address[] calldata collateralTokens,
        address[] calldata priceFeedAddress
    ) external;

    function updateTreasury(address newTreasuryAddress) external;

    // --- Flash Loan Functions (IERC3156FlashLender) ---

    function flashLoan(
        IERC3156FlashBorrower receiver,
        address token,
        uint256 amount,
        bytes calldata data
    ) external override returns (bool);

    function flashFee(
        address token,
        uint256 amount
    ) external view override returns (uint256);

    function maxFlashLoan(
        address token
    ) external view override returns (uint256);

    // --- View Functions ---

    function getStblUSD() external view returns (address);

    function MAX_LTV() external view returns (uint256);

    function getUserPositionIds(
        address user
    ) external view returns (uint256[] memory);

    function getPosition(
        uint256 positionId
    ) external view returns (Position memory);

    function getPositionLTV(uint256 positionId) external view returns (uint256);

    function getPositionCollateralValue(
        uint256 positionId
    ) external view returns (uint256);

    function getTokenUsdValue(
        address token,
        uint256 amount
    ) external view returns (uint256);
}
