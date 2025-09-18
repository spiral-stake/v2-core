// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import {IPAllActionV3, SwapData, LimitOrderData, ApproxParams, TokenInput} from "@pendle/core-v2/contracts/interfaces/IPAllActionV3.sol";
import {IFlashLeverageCore, LeverageParams, UnleverageParams, CoreLeveragePosition} from "../../interfaces/IFlashLeverageCore.sol";
import {SwapParams} from "../structs/SwapParams.sol";
import {LeveragePosition} from "../structs/LeveragePosition.sol";
import {CollateralTokenConfig} from "../structs/CollateralTokenConfig.sol";
import {TokenHelper} from "../libraries/TokenHelper.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Math} from "../libraries/Math.sol";
import {FLError} from "../libraries/Error.sol";
import {IPendleMarket} from "../../interfaces/IPendleMarket.sol";
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

    /// @notice Fee percentage in basis points (10%)
    uint256 public constant YIELD_FEE = 10e16;

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
        uint256 indexed positionId,
        uint256 indexed amountDepositedInLoanToken
    );

    event LeveragePositionClosed(
        address indexed user,
        uint256 indexed positionId,
        uint256 indexed amountReturnedInLoanToken
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

    /// @notice Validates that the desired LTV does not exceed the maximum allowed LTV for the market.
    /// @dev Prevents positions that would be immediately liquidatable or unsafe.
    /// @param desiredLtv The desired loan-to-value ratio to validate.
    /// @param collateralToken The address of the collateral token.
    /// @param loanToken The address of the loan token.
    modifier validateDesiredLtv(
        uint256 desiredLtv,
        address collateralToken,
        address loanToken
    ) {
        require(
            desiredLtv <=
                i_flashLeverageCore.getMaxLtv(collateralToken, loanToken),
            FLError.FlashLeverage__ExceedsMaxLTV()
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
        validateDesiredLtv(
            leverageParams.desiredLtv,
            leverageParams.collateralToken,
            leverageParams.loanToken
        )
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
        validateDesiredLtv(
            leverageParams.desiredLtv,
            leverageParams.collateralToken,
            leverageParams.loanToken
        )
    {
        _transferIn(swapParams.tokenIn, msg.sender, swapParams.amountTokenIn);

        if (swapParams.tokenIn != leverageParams.collateralToken) {
            _handleTokenSwap(leverageParams.collateralToken, swapParams);
        }

        _leverage(onBehalfOf, leverageParams);
    }

    /**
     * @notice Closes an open leverage position and withdraws collateral.
     * @param positionId The ID of the position to close.
     * @param pendleSwap Address of the Pendle swap contract to use.
     * @param tokenRedeemSy Address of the token to redeem from SY (Standardized Yield) tokens
     * @param swapData Additional swap data required by Pendle.
     * @param limitOrderData Limit order parameters for the swap.
     * @dev Public entry point that validates position and delegates to internal implementation
     */
    function unleverage(
        address user,
        uint256 positionId,
        address pendleSwap,
        address tokenRedeemSy,
        uint256 minTokenOut,
        SwapData calldata swapData,
        LimitOrderData calldata limitOrderData
    ) external returns (uint256 amountReturned) {
        require(
            positionId < s_userLeveragePositions[user].length,
            FLError.FlashLeverage__PositionDoesNotExist()
        );

        LeveragePosition storage position = s_userLeveragePositions[user][
            positionId
        ];

        if (_ptNotExpired(position.collateralToken)) {
            require(
                msg.sender == user,
                FLError.FlashLeverage__OnlyOwnerCanCloseBeforeMaturity()
            );
        }

        require(
            position.open,
            FLError.FlashLeverage__PositionAlreadyUnleveraged()
        );

        return
            _unleverage(
                user,
                positionId,
                position,
                pendleSwap,
                tokenRedeemSy,
                minTokenOut,
                swapData,
                limitOrderData
            );
    }

    /**
     * @notice Allows owner to add support for new collateral tokens.
     * @param tokenConfigs Array of token configurations including swap and market parameters.
     * @dev For each token, maps it to its Pendle market and approves max spending to flash leverage core
     */
    function addSupportedCollateralTokens(
        CollateralTokenConfig[] calldata tokenConfigs
    ) external onlyOwner {
        for (uint256 i; i < tokenConfigs.length; ++i) {
            CollateralTokenConfig memory config = tokenConfigs[i];
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
    function renounceOwnership() public override(Ownable) {}

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

        // Position Tracking Related: Amount Collateral Deposited in loan token
        uint256 amountCollateralInLoanToken = i_flashLeverageCore
            .getCollateralValueInLoanToken(
                collateralToken,
                loanToken,
                amountCollateral
            )
            .scaleTo(
                Math.STANDARD_DECIMALS,
                IERC20Metadata(loanToken).decimals()
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
                amountLeveragedCollateral: amountLeveragedCollateral,
                sharesBorrowed: sharesBorrowed
            })
        );

        emit LeveragePositionOpened(
            onBehalfOf,
            positionId,
            amountCollateralInLoanToken
        );
    }

    /** @notice Internal function to execute unleverage operations
     * @param user Address of the position owner
     * @param positionId The ID of the position to close
     * @param position Storage reference to the position being closed
     * @param pendleSwap Address of the Pendle swap contract to use
     * @param tokenRedeemSy Address of the token to redeem from SY tokens
     * @param swapData Additional swap data required by Pendle
     * @param limitOrderData Limit order parameters for the swap
     * @dev Executes core unleverage, calculates fees, and handles token transfers
     */
    function _unleverage(
        address user,
        uint256 positionId,
        LeveragePosition storage position,
        address pendleSwap,
        address tokenRedeemSy,
        uint256 minTokenOut,
        SwapData calldata swapData,
        LimitOrderData calldata limitOrderData
    ) internal returns (uint256 amountReturned) {
        // Execute core unleverage operation
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
                minTokenOut: minTokenOut,
                swapData: swapData,
                limitOrderData: limitOrderData
            })
        );

        // Mark position as closed
        position.open = false;

        // Calculate amounts and fees
        // All calculations are in loan token, but 18 decimals for standardisation in calculations
        uint8 loanTokenDecimals = IERC20Metadata(position.loanToken).decimals();

        uint256 totalAmountDeposited = position
            .amountCollateralInLoanToken
            .scaleTo(loanTokenDecimals, Math.STANDARD_DECIMALS);
        uint256 totalAmountReceived = _selfBalance(position.loanToken).scaleTo(
            loanTokenDecimals,
            Math.STANDARD_DECIMALS
        );

        // Handle yield fee calculation and transfer
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

        // Transfer remaining amount to user
        amountReturned = (totalAmountReceived - amountFee).scaleTo(
            Math.STANDARD_DECIMALS,
            loanTokenDecimals
        );
        _transferOut(position.loanToken, user, amountReturned);

        emit LeveragePositionClosed(user, positionId, amountReturned);
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
            swapParams.minPtOut,
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

    function _ptNotExpired(
        address collateralToken
    ) internal view returns (bool) {
        return !IPendleMarket(s_pendleMarket[collateralToken]).isExpired();
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
     * @notice Returns the current treasury address
     * @return treasury The address of the current treasury
     */
    function getTreasury() public view returns (address) {
        return s_treasury;
    }
}
