// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import {IPAllActionV3, SwapData, LimitOrderData, ApproxParams, TokenInput} from "@pendle/core-v2/contracts/interfaces/IPAllActionV3.sol";
import {IFlashLeverageCore, LeverageParams, UnleverageParams, CoreLeveragePosition} from "../../interfaces/IFlashLeverageCore.sol";
import {SwapParams} from "../structs/SwapParams.sol";
import {LeveragePosition} from "../structs/LeveragePosition.sol";
import {CollateralTokenConfig} from "../structs/CollateralTokenConfig.sol";
import {TokenHelper, IERC20} from "../libraries/TokenHelper.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Math} from "../libraries/Math.sol";
import {FLError} from "../libraries/Error.sol";

/**
 * @title FlashLeverage
 * @notice A wrapper contract that enables leveraged positions using flash loans with automatic token swapping
 * @dev This contract acts as an intermediary between users and the flash leverage system, handling token swaps via Pendle
 */

contract FlashLeverage is TokenHelper, Ownable2Step {
    using Math for uint256;

    /////////////////////////
    // Constants and Immutables

    /// @notice Pendle router for executing token swaps
    IPAllActionV3 public immutable i_pendleRouter;

    /// @notice Flash leverage contract for executing leveraged positions
    IFlashLeverageCore public immutable i_flashLeverageCore;

    /////////////////////////
    // Storage

    mapping(address user => LeveragePosition[]) private s_userLeveragePositions;

    /// @notice Mapping of PT collateral tokens to their pendle market
    mapping(address collateralToken => address pendleMarket)
        private s_pendleMarket;

    /////////////////////////
    // Events

    event LeveragePositionOpened(
        address indexed user,
        uint256 indexed positionId
    );

    event LeveragePositionClosed(
        address indexed user,
        uint256 indexed positionId,
        uint256 indexed amountReturned
    );

    /////////////////////////
    // Modifiers

    /**
     * @notice Validates that the provided amount is greater than zero
     * @param value The amount to validate
     */
    modifier validateAmount(uint256 value) {
        require(value > 0, FLError.FlashLeverage__AmountCannotBeZero());
        _;
    }

    /**
     * @dev Validates if the onBehalfOf address is not a zero address
     * @param onBehalfOf onBehalfOf address
     *
     * Reverts if the onBehalfOf address is a zero address
     */
    modifier validateOnBehalfOf(address onBehalfOf) {
        require(
            onBehalfOf != address(0),
            FLError.FlashLeverage__InvalidOnBehalfOfAddress()
        );
        _;
    }

    /////////////////////////
    // Constructor

    /**
     * @notice Initializes the wrapper with required contract addresses
     * @param flashLeverageCore Address of the flash leverage contract
     * @param pendleRouter Address of the Pendle router contract
     */
    constructor(
        address flashLeverageCore,
        address pendleRouter
    ) Ownable(msg.sender) {
        i_flashLeverageCore = IFlashLeverageCore(flashLeverageCore);
        i_pendleRouter = IPAllActionV3(pendleRouter);
    }

    /////////////////////////
    // External Functions

    /**
     * @notice Executes the flash leverage using PT collateral
     * @param leverageParams Parameters for the flash leverage operation
     */
    function leverage(
        address onBehalfOf,
        LeverageParams calldata leverageParams
    )
        external
        validateOnBehalfOf(onBehalfOf)
        validateAmount(leverageParams.amountCollateral)
    {
        require(
            s_pendleMarket[leverageParams.collateralToken] != address(0),
            FLError.FlashLeverage__UnsupportedCollateralToken()
        );

        _transferIn(
            leverageParams.collateralToken,
            msg.sender,
            leverageParams.amountCollateral
        );

        _leverage(onBehalfOf, leverageParams);
    }

    /**
     * @notice Entry point for users. Swaps tokens if needed, approves, then leverages.
     * @param swapParams Parameters including tokenIn, amountTokenIn
     * @param leverageParams Parameters for the leverage call
     */
    function swapAndLeverage(
        address onBehalfOf,
        SwapParams calldata swapParams,
        LeverageParams calldata leverageParams
    )
        external
        validateOnBehalfOf(onBehalfOf)
        validateAmount(swapParams.amountTokenIn)
        validateAmount(leverageParams.amountCollateral)
    {
        address collateralToken = leverageParams.collateralToken;
        require(
            s_pendleMarket[collateralToken] != address(0),
            FLError.FlashLeverage__UnsupportedCollateralToken()
        );

        // Transfer tokens from user
        IERC20(swapParams.tokenIn).transferFrom(
            msg.sender,
            address(this),
            swapParams.amountTokenIn
        );

        // Swap if needed
        if (swapParams.tokenIn != collateralToken) {
            _handleTokenSwap(collateralToken, swapParams);
        }

        // Call internal leverage
        _leverage(onBehalfOf, leverageParams);
    }

    /**
     * @notice Closes an open leverage position and withdraws collateral.
     * @param positionId The ID of the position to close.
     * @param pendleSwap Address of the Pendle swap contract to use.
     * @param swapData Additional swap data required by Pendle.
     * @param limitOrderData Limit order parameters for the swap.
     */
    function unleverage(
        uint256 positionId,
        address pendleSwap,
        address tokenRedeemSy,
        SwapData calldata swapData,
        LimitOrderData calldata limitOrderData
    ) external {
        address _msgSender = msg.sender;

        require(
            positionId < s_userLeveragePositions[_msgSender].length,
            FLError.FlashLeverage__PositionDoesNotExist()
        );
        LeveragePosition storage position = s_userLeveragePositions[_msgSender][
            positionId
        ];
        require(
            position.open,
            FLError.FlashLeverage__PositionAlreadyUnleveraged()
        );

        i_flashLeverageCore.unleverage(
            UnleverageParams({
                collateralToken: position.collateralToken,
                loanToken: position.loanToken,
                sharesToBurn: position.sharesBorrowed,
                amountCollateralToWithdraw: position.amountLeveragedCollateral,
                pendleSwap: pendleSwap,
                tokenRedeemSy: tokenRedeemSy,
                swapData: swapData,
                limitOrderData: limitOrderData
            })
        );

        position.open = false;

        uint256 amountReturned = _selfBalance(position.loanToken);
        _transferOut(position.loanToken, _msgSender, amountReturned);

        emit LeveragePositionClosed(_msgSender, positionId, amountReturned);
    }

    /**
     * @notice Allows owner to add support for new collateral tokens.
     * @param configs Array of token configurations including swap and market parameters.
     */
    function addSupportedCollateralTokens(
        CollateralTokenConfig[] calldata configs
    ) external onlyOwner {
        for (uint256 i; i < configs.length; ++i) {
            CollateralTokenConfig memory config = configs[i];
            s_pendleMarket[config.collateralToken] = config.pendleMarket;

            // Safe approve max collateral token to i_flashLeverage for lifetime
            _safeApprove(
                config.collateralToken,
                address(i_flashLeverageCore),
                type(uint256).max
            );
        }
    }

    /**
     * @notice Overrides renounceOwnership to prevent ownership renunciation
     * @dev Intentionally disabled to retain upgradeability and integration support management
     */
    function renounceOwnership() public override {}

    /////////////////////////
    // Internal Functions

    function _leverage(
        address onBehalfOf,
        LeverageParams calldata leverageParams
    ) internal {
        address collateralToken = leverageParams.collateralToken;
        address loanToken = leverageParams.loanToken;
        uint256 amountCollateral = leverageParams.amountCollateral;

        // Position before
        CoreLeveragePosition memory positionBefore = i_flashLeverageCore
            .getCoreLeveragePosition(address(this), collateralToken, loanToken);

        // Leverage
        i_flashLeverageCore.leverage(leverageParams);

        // Position after
        CoreLeveragePosition memory positionAfter = i_flashLeverageCore
            .getCoreLeveragePosition(address(this), collateralToken, loanToken);

        uint256 collateralTokenUsdValue = i_flashLeverageCore
            .getCollateralValueInLoanToken(
                collateralToken,
                loanToken,
                Math.ONE
            );

        // Add new Leverage Position
        uint256 positionId = s_userLeveragePositions[onBehalfOf].length;
        s_userLeveragePositions[onBehalfOf].push(
            LeveragePosition({
                open: true,
                collateralToken: collateralToken,
                loanToken: loanToken,
                collateralTokenUsdValue: collateralTokenUsdValue,
                amountCollateral: amountCollateral,
                amountLeveragedCollateral: positionAfter.amountCollateral -
                    positionBefore.amountCollateral,
                sharesBorrowed: positionAfter.sharesBorrowed -
                    positionBefore.sharesBorrowed
            })
        );

        emit LeveragePositionOpened(onBehalfOf, positionId);
    }

    /**
     * @notice Swaps input tokens to collateral tokens via Pendle
     * @dev Uses stored swap parameters and handles excess token refunds
     * @param swapParams Wrapper parameters containing swap details
     */
    function _handleTokenSwap(
        address collateralToken,
        SwapParams calldata swapParams
    ) internal {
        // Approve Pendle router to spend input tokens
        _forceApprove(
            swapParams.tokenIn,
            address(i_pendleRouter),
            swapParams.amountTokenIn
        );

        // Execute swap from input token to PT (Principal Token)
        i_pendleRouter.swapExactTokenForPt(
            address(this),
            s_pendleMarket[collateralToken],
            swapParams.minOut,
            swapParams.approxParams,
            TokenInput({
                tokenIn: swapParams.tokenIn,
                netTokenIn: swapParams.amountTokenIn,
                tokenMintSy: swapParams.tokenMintSy,
                pendleSwap: swapParams.pendleSwap,
                swapData: swapParams.swapData
            }),
            swapParams.limitOrderData
        );

        // Return any excess collateral tokens to user or let it accumulate as dust (gas-efficient)
        // if (amountCollateralOut > swapParams.minOut) {
        //     uint256 amountRemaining;
        //     unchecked {
        //         amountRemaining = amountCollateralOut - swapParams.minOut;
        //     }
        //     _transferOut(collateralToken, msg.sender, amountRemaining);
        // }
    }

    /**
     * @notice Returns all leverage positions for a specific user.
     * @param user The address of the user.
     * @return positions Array of leverage positions.
     */
    function getUserLeveragePositions(
        address user
    ) public view returns (LeveragePosition[] memory) {
        return s_userLeveragePositions[user];
    }

    /**
     * @notice Returns all leverage positions for a specific user.
     * @param user Address of the user
     * @param positionId Id of the leverage position
     */
    function getUserLeveragePosition(
        address user,
        uint256 positionId
    ) public view returns (LeveragePosition memory) {
        return s_userLeveragePositions[user][positionId];
    }
}
