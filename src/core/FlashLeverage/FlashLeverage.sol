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
import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";

/**
 * @title FlashLeverage
 * @notice A wrapper contract that enables leveraged positions using flash loans with automatic token swapping
 * @dev This contract acts as an intermediary between users and the flash leverage system, handling token swaps via Pendle
 */

contract FlashLeverage is TokenHelper, Ownable2Step {
    using Math for uint256;

    /////////////////////////
    // Constants and Immutables

    /// @notice Fee percentage in basis points (5%)
    uint256 public constant YIELD_FEE = 5e16;

    /// @notice Pendle router for executing token swaps
    IPAllActionV3 public immutable i_pendleRouter;

    /// @notice Flash leverage contract for executing leveraged positions
    IFlashLeverageCore public immutable i_flashLeverageCore;

    /////////////////////////
    // Storage

    /// @notice Treasury address to receive fees
    address private s_treasury;

    /// @notice Mapping of PT collateral tokens to their pendle market
    mapping(address collateralToken => address pendleMarket)
        private s_pendleMarket;

    mapping(address user => LeveragePosition[]) private s_userLeveragePositions;

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

    /**
     * @notice Validates that the provided amount is greater than zero
     * @param value The amount to validate
     */
    modifier validateAmount(uint256 value) {
        require(value > 0, FLError.FlashLeverage__AmountCannotBeZero());
        _;
    }

    /// @notice Validates that the collateral token is supported for leveraging.
    /// @param collateralToken The address of the collateral token to validate.
    modifier validateCollateralToken(address collateralToken) {
        require(
            isSupportedCollateralToken(collateralToken),
            FLError.FlashLeverage__UnsupportedCollateralToken()
        );
        _;
    }

    /////////////////////////
    // Constructor

    /**
     * @notice Initializes the wrapper with required contract addresses
     * @param flashLeverageCore Address of the flash leverage contract
     * @param pendleRouter Address of the Pendle router contract
     * @param treasury Address to receive yield fees
     */
    constructor(
        address flashLeverageCore,
        address pendleRouter,
        address treasury
    ) Ownable(msg.sender) {
        i_flashLeverageCore = IFlashLeverageCore(flashLeverageCore);
        i_pendleRouter = IPAllActionV3(pendleRouter);
        s_treasury = treasury;
    }

    /////////////////////////
    // External Functions

    /**
     * @notice Executes the flash leverage using PT collateral
     * @param onBehalfOf Address to open the position on behalf of
     * @param leverageParams Parameters for the flash leverage operation
     */
    function leverage(
        address onBehalfOf,
        LeverageParams calldata leverageParams
    )
        external
        validateOnBehalfOf(onBehalfOf)
        validateCollateralToken(leverageParams.collateralToken)
        validateAmount(leverageParams.amountCollateral)
    {
        _transferIn(
            leverageParams.collateralToken,
            msg.sender,
            leverageParams.amountCollateral
        );

        _leverage(onBehalfOf, leverageParams);
    }

    /**
     * @notice Entry point for users. Swaps tokens if needed, approves, then leverages.
     * @param onBehalfOf Address to open the position on behalf of
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
        validateCollateralToken(leverageParams.collateralToken)
        validateAmount(swapParams.amountTokenIn)
        validateAmount(leverageParams.amountCollateral)
    {
        // Transfer tokens from user
        IERC20(swapParams.tokenIn).transferFrom(
            msg.sender,
            address(this),
            swapParams.amountTokenIn
        );

        // Swap if needed
        if (swapParams.tokenIn != leverageParams.collateralToken) {
            _handleTokenSwap(leverageParams.collateralToken, swapParams);
        }

        // Call internal leverage
        _leverage(onBehalfOf, leverageParams);
    }

    /**
     * @notice Closes an open leverage position and withdraws collateral.
     * @param positionId The ID of the position to close.
     * @param pendleSwap Address of the Pendle swap contract to use.
     * @param tokenRedeemSy Address of the token to redeem from SY (Standardized Yield) tokens
     * @param swapData Additional swap data required by Pendle.
     * @param limitOrderData Limit order parameters for the swap.
     * @dev Calculates yield and deducts 5% fee on positive yields before returning funds to user
     */
    function unleverage(
        uint256 positionId,
        address pendleSwap,
        address tokenRedeemSy,
        SwapData calldata swapData,
        LimitOrderData calldata limitOrderData
    ) external returns (uint256 amountReturned) {
        address user = msg.sender;

        require(
            positionId < s_userLeveragePositions[user].length,
            FLError.FlashLeverage__PositionDoesNotExist()
        );
        LeveragePosition storage position = s_userLeveragePositions[user][
            positionId
        ];
        require(
            position.open,
            FLError.FlashLeverage__PositionAlreadyUnleveraged()
        );

        i_flashLeverageCore.unleverage(
            user,
            UnleverageParams({
                collateralToken: position.collateralToken,
                loanToken: position.loanToken,
                desiredLtv: position.desiredLtv,
                sharesToBurn: position.sharesBorrowed,
                amountCollateralToWithdraw: position.amountLeveragedCollateral,
                pendleSwap: pendleSwap,
                tokenRedeemSy: tokenRedeemSy,
                swapData: swapData,
                limitOrderData: limitOrderData
            })
        );
        position.open = false;

        uint8 loanTokenDecimals = IERC20Metadata(position.loanToken).decimals();
        uint256 totalAmountDeposited = position.amountCollateralInLoanToken;
        uint256 totalAmountReceived = _selfBalance(position.loanToken).scaleTo(
            loanTokenDecimals,
            Math.STANDARD_DECIMALS
        );

        uint256 amountFee;
        if (totalAmountReceived > totalAmountDeposited) {
            uint256 yieldGenerated = totalAmountReceived - totalAmountDeposited;
            amountFee = yieldGenerated.mulDown(YIELD_FEE);
            _transferOut(
                position.loanToken,
                s_treasury,
                amountFee.scaleTo(Math.STANDARD_DECIMALS, loanTokenDecimals)
            );
        }

        amountReturned = (totalAmountReceived - amountFee).scaleTo(
            Math.STANDARD_DECIMALS,
            loanTokenDecimals
        );
        _transferOut(position.loanToken, user, amountReturned);
        emit LeveragePositionClosed(user, positionId, amountReturned);
    }

    /**
     * @notice Allows owner to add support for new collateral tokens.
     * @param tokensConfig Array of token configurations including swap and market parameters.
     * @dev For each token, maps it to its Pendle market and approves max spending to flash leverage core
     */
    function addSupportedCollateralTokens(
        CollateralTokenConfig[] calldata tokensConfig
    ) external onlyOwner {
        for (uint256 i; i < tokensConfig.length; ++i) {
            CollateralTokenConfig memory config = tokensConfig[i];
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
     * @notice Updates the treasury address
     * @param newTreasury The new treasury address
     * @dev Only callable by the contract owner. Validates that the new treasury is not zero address.
     */
    function updateTreasury(address newTreasury) external onlyOwner {
        require(
            newTreasury != address(0),
            FLError.FlashLeverage__TreasuryCannotBeZero()
        );

        s_treasury = newTreasury;
    }

    /**
     * @notice Overrides renounceOwnership to prevent ownership renunciation
     * @dev Intentionally disabled to retain upgradeability and integration support management
     */
    function renounceOwnership() public pure override {
        revert FLError.FlashLeverage__RenounceOwnershipDisabled();
    }

    /////////////////////////
    // Internal Functions

    /**
     * @notice Internal function to execute leverage operations
     * @param onBehalfOf Address to open the position on behalf of
     * @param leverageParams Parameters for the leverage operation
     * @dev Compares position before and after leverage to track deltas and store position data
     */
    function _leverage(
        address onBehalfOf,
        LeverageParams calldata leverageParams
    ) internal {
        address collateralToken = leverageParams.collateralToken;
        address loanToken = leverageParams.loanToken;
        uint256 desiredLtv = leverageParams.desiredLtv;
        uint256 amountCollateral = leverageParams.amountCollateral;

        // Position before
        CoreLeveragePosition memory positionBefore = i_flashLeverageCore
            .getUserCoreLeveragePosition(
                onBehalfOf,
                desiredLtv,
                collateralToken,
                loanToken
            );

        // Leverage
        i_flashLeverageCore.leverage(onBehalfOf, leverageParams);

        // Position after
        CoreLeveragePosition memory positionAfter = i_flashLeverageCore
            .getUserCoreLeveragePosition(
                onBehalfOf,
                desiredLtv,
                collateralToken,
                loanToken
            );

        // Position Related: Amount Leveraged & Shares Borrowed
        uint256 amountLeveragedCollateral = positionAfter.amountCollateral -
            positionBefore.amountCollateral;
        uint256 sharesBorrowed = positionAfter.sharesBorrowed -
            positionBefore.sharesBorrowed;

        // Position Tracking Related
        uint256 amountCollateralInLoanToken = i_flashLeverageCore
            .getCollateralValueInLoanToken(
                collateralToken,
                loanToken,
                amountCollateral
            );
        uint256 positionValueInLoanToken = _calcPositionValueInLoanToken(
            collateralToken,
            loanToken,
            amountLeveragedCollateral,
            sharesBorrowed
        );

        // Add new Leverage Position
        uint256 positionId = s_userLeveragePositions[onBehalfOf].length;
        s_userLeveragePositions[onBehalfOf].push(
            LeveragePosition({
                open: true,
                collateralToken: collateralToken,
                loanToken: loanToken,
                desiredLtv: desiredLtv,
                amountCollateral: amountCollateral,
                amountCollateralInLoanToken: amountCollateralInLoanToken,
                positionValueInLoanToken: positionValueInLoanToken,
                amountLeveragedCollateral: amountLeveragedCollateral,
                sharesBorrowed: sharesBorrowed
            })
        );

        emit LeveragePositionOpened(onBehalfOf, positionId);
    }

    /**
     * @notice Swaps input tokens to collateral tokens via Pendle
     * @param collateralToken The target collateral token to swap to
     * @param swapParams Wrapper parameters containing swap details
     * @dev Uses stored swap parameters and handles token approvals for Pendle router
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
    }

    /**
     * @notice Calculates the net position value in loan token terms
     * @param collateralToken Address of the collateral token
     * @param loanToken Address of the loan token
     * @param amountLeveragedCollateral Amount of leveraged collateral
     * @param sharesBorrowed Amount of shares borrowed
     * @return Net position value (collateral value minus borrowed shares value) in 18 decimals
     */
    function _calcPositionValueInLoanToken(
        address collateralToken,
        address loanToken,
        uint256 amountLeveragedCollateral,
        uint256 sharesBorrowed
    ) internal view returns (uint256) {
        uint256 collateralValue = i_flashLeverageCore
            .getCollateralValueInLoanToken(
                collateralToken,
                loanToken,
                amountLeveragedCollateral
            );
        uint256 sharesValue = i_flashLeverageCore.getSharesValueInLoanToken(
            collateralToken,
            loanToken,
            sharesBorrowed
        );

        return collateralValue - sharesValue;
    }

    /////////////////////////
    // View Functions

    function isSupportedCollateralToken(
        address collateralToken
    ) public view returns (bool) {
        return s_pendleMarket[collateralToken] != address(0);
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
     * @notice Returns a specific leverage position for a user.
     * @param user Address of the user
     * @param positionId Id of the leverage position
     * @return position The leverage position struct
     */
    function getUserLeveragePosition(
        address user,
        uint256 positionId
    ) public view returns (LeveragePosition memory) {
        return s_userLeveragePositions[user][positionId];
    }

    /**
     * @notice Calculates the yield generated on a specific position
     * @param user Address of the user
     * @param positionId Id of the leverage position
     * @return yield The yield generated in loan token terms with 18 decimals, returns 0 if position is at a loss
     */
    function getPositionYieldInLoanToken(
        address user,
        uint256 positionId
    ) public view returns (uint256) {
        LeveragePosition memory position = s_userLeveragePositions[user][
            positionId
        ];

        uint256 initialPositionValue = position.positionValueInLoanToken;
        uint256 currentPositionValue = _calcPositionValueInLoanToken(
            position.collateralToken,
            position.loanToken,
            position.amountLeveragedCollateral,
            position.sharesBorrowed
        );

        // Return 0 if current value is less than initial (no yield/loss)
        if (currentPositionValue <= initialPositionValue) {
            return 0;
        }

        return (currentPositionValue - initialPositionValue);
    }

    /**
     * @notice Returns the current treasury address
     * @return treasury The address of the current treasury
     */
    function getTreasury() public view returns (address) {
        return s_treasury;
    }
}
