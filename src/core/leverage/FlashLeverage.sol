// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

/// @title FlashLeverage
/// @author
/// @notice Provides flashloan-based leveraged yield on stable PT-collateral (PENDLE) using morpho markets.
/// @dev Integrates with Morpho, Pendle, and custom SwapAggregator and MarketPositionManager modules.
/// @dev loanToken Fixed to USDC (6 decimals).

import {SwapAggregator, SwapParams, SwapData, ApproxParams, LimitOrderData} from "./SwapAggregator.sol";
import {MarketPositionManager, MarketParams, Id} from "./MarketPositionManager.sol";
import {LeveragePosition} from "../structs/LeveragePosition.sol";
import {CollateralTokenConfig} from "../structs/CollateralTokenConfig.sol";
import {IOracleRouter} from "../../interfaces/IOracleRouter.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import {Math} from "../libraries/Math.sol";
import {Error} from "../libraries/Errors.sol";

contract FlashLeverage is SwapAggregator, MarketPositionManager, Ownable2Step {
    using Math for uint256;

    /////////////////////////
    // Constants and Immutables

    /// @notice USD reference address used in price feeds (e.g., Chainlink).
    address public constant USD = 0x0000000000000000000000000000000000000348;

    /// @notice Buffer subtracted from liquidation LTV to reduce liquidation risk (5%).
    uint256 public constant LIQUIDATION_BUFFER = 50e15;

    /// @notice Max collateral amount allowed per leverage (100 PT tokens).
    uint256 public constant AMOUNT_COLLATERAL_CAP = 100e18;

    /// @notice Oracle router used for fetching USD price quotes.
    IOracleRouter public immutable i_oracleRouter;

    /////////////////////////
    // Storage

    mapping(address user => LeveragePosition[]) private s_userLeveragePositions;

    /////////////////////////
    // Events

    event LeveragePositionOpened(
        address indexed user,
        uint256 indexed positionId,
        address collateralToken,
        address loanToken,
        uint256 amountUserCollateral,
        uint256 amountTotalCollateral,
        uint256 sharesBorrowed
    );

    event LeveragePositionClosed(
        address indexed user,
        uint256 indexed positionId,
        uint256 indexed amountReturned
    );

    event CollateralTokenAdded(
        address indexed token,
        address indexed pendleMarket,
        bytes32 indexed morphoMarketId
    );

    /////////////////////////
    // Modifiers

    /**
     * @dev Validates the amount of collateral is within acceptable bounds.
     * @param value Collateral amount to validate.
     *
     * Reverts if value is 0 or exceeds `AMOUNT_COLLATERAL_CAP`.
     */
    modifier validateAmountCollateral(uint256 value) {
        require(
            value > 0 && value <= AMOUNT_COLLATERAL_CAP,
            Error.FlashLeverage__InvalidAmountCollateral()
        );
        _;
    }

    /////////////////////////
    // Constructor

    /**
     * @notice Initializes the FlashLeverage contract.
     * @param morphoAddress Address of the Morpho protocol contract.
     * @param pendleRouter Address of the Pendle router for swap execution.
     * @param oracleRouter Address of the oracle router for price feeds.
     */
    constructor(
        address morphoAddress,
        address pendleRouter,
        address oracleRouter
    )
        Ownable(msg.sender)
        SwapAggregator(pendleRouter)
        MarketPositionManager(morphoAddress)
    {
        i_oracleRouter = IOracleRouter(oracleRouter);
    }

    /////////////////////////
    // External Functions

    /**
     * @notice Opens a leveraged position by supplying stable PT-collateral and borrowing stablecoins via flashloan.
     * @param onBehalfOf Address that receives the leveraged position.
     * @param collateralToken Token used as collateral (e.g., PT-sUSDe, PT-USR tokens).
     * @param amountCollateral Amount of user-supplied PT-collateral.
     * @param approxParams Pendle approximation parameters for slippage-tolerant swaps.
     * @param pendleSwap Address of Pendle's swap adapter.
     * @param swapData Swap path and execution details.
     * @param limitOrderData Optional limit order data for swap.
     *
     * Emits a {LeveragePositionOpened} event.
     */
    function leverage(
        address onBehalfOf,
        address collateralToken,
        uint256 amountCollateral,
        ApproxParams memory approxParams,
        address pendleSwap,
        SwapData memory swapData,
        LimitOrderData memory limitOrderData
    ) external validateAmountCollateral(amountCollateral) {
        address loanToken = s_marketParams[collateralToken].loanToken;
        require(
            loanToken != address(0),
            Error.FlashLeverage__UnsupportedCollateralToken()
        );

        _transferIn(collateralToken, msg.sender, amountCollateral);

        uint256 amountLoan = calcLoanAmount(
            collateralToken,
            loanToken,
            amountCollateral
        );

        uint256 positionId = s_userLeveragePositions[onBehalfOf].length;
        s_userLeveragePositions[onBehalfOf].push(
            LeveragePosition({
                collateralToken: collateralToken,
                loanToken: loanToken,
                amountUserCollateral: amountCollateral,
                amountTotalCollateral: 0, // gets set in _handleLeverage
                sharesBorrowed: 0 // gets set in _handleLeverage
            })
        );

        bytes memory data = abi.encode(
            Action.LEVERAGE,
            onBehalfOf,
            positionId,
            approxParams,
            pendleSwap,
            swapData,
            limitOrderData
        );

        i_morpho.flashLoan(loanToken, amountLoan, data);
    }

    /**
     * @notice Closes an existing leveraged position and returns the remaining amount (in USDC) to the user.
     * @param positionId Index of the user's leverage position to close.
     * @param pendleSwap Address of Pendle's swap adapter.
     * @param swapData Swap path and execution details.
     * @param limitOrderData Optional limit order data for swap.
     *
     * Emits a {LeveragePositionClosed} event.
     */
    function unleverage(
        uint256 positionId,
        address pendleSwap,
        SwapData memory swapData,
        LimitOrderData memory limitOrderData
    ) external {
        address _msgSender = msg.sender;

        require(
            positionId < s_userLeveragePositions[_msgSender].length,
            Error.FlashLeverage__PositionDoesNotExist()
        );
        LeveragePosition memory position = s_userLeveragePositions[_msgSender][
            positionId
        ];
        require(
            position.loanToken != address(0),
            Error.FlashLeverage__PositionAlreadyUnleveraged()
        );

        bytes memory data = abi.encode(
            Action.UNLEVERAGE,
            _msgSender,
            positionId,
            pendleSwap,
            swapData,
            limitOrderData
        );

        uint256 amountLoan = getRepayAmount(
            position.collateralToken,
            position.sharesBorrowed
        );

        i_morpho.flashLoan(position.loanToken, amountLoan, data);

        delete s_userLeveragePositions[_msgSender][positionId];
    }

    /////////////////////////
    // Internal Functions

    /**
     * @dev Handles internal logic after flashloan is received for leveraging.
     *      Swaps borrowed tokens to PT-collateral, deposits the total PT-collateral,
     *      to borrow again and repay flashloan.
     * @param amountLoan Amount borrowed via flashloan.
     * @param data Encoded leverage action data.
     */
    function _handleLeverage(
        uint256 amountLoan,
        bytes memory data
    ) internal override {
        (
            ,
            address user,
            uint256 positionId,
            ApproxParams memory approxParams,
            address pendleSwap,
            SwapData memory swapData,
            LimitOrderData memory limitOrderData
        ) = abi.decode(
                data,
                (
                    Action,
                    address,
                    uint256,
                    ApproxParams,
                    address,
                    SwapData,
                    LimitOrderData
                )
            );

        LeveragePosition storage position = s_userLeveragePositions[user][
            positionId
        ];

        // Swap USDC loan -> PT collateral
        uint256 amountSwappedCollateralToken = _swapLoanTokenToCollateralToken(
            position.loanToken,
            position.collateralToken,
            amountLoan,
            approxParams,
            pendleSwap,
            swapData,
            limitOrderData
        );
        position.amountTotalCollateral =
            position.amountUserCollateral +
            amountSwappedCollateralToken;

        // Supply total collateral and borrow USDC
        uint256 sharesBorrowed = _supplyCollateralAndBorrow(
            position.collateralToken,
            position.amountTotalCollateral,
            amountLoan
        );
        position.sharesBorrowed = sharesBorrowed;

        // Repay the flash loan, with borrowed USDC
        _forceApprove(position.loanToken, address(i_morpho), amountLoan);

        emit LeveragePositionOpened(
            user,
            positionId,
            position.collateralToken,
            position.loanToken,
            position.amountUserCollateral,
            position.amountTotalCollateral,
            position.sharesBorrowed
        );
    }

    /**
     * @dev Handles internal logic after flashloan is received for unleveraging.
     *      Repays existing borrow, withdraws PT-collateral, swaps it to the loan token(USDC),
     *      repays the flashloan, and returns excess to user (User's initial + leveraged yield)
     * @param amountLoan Amount borrowed via flashloan for debt repayment.
     * @param data Encoded unleverage action data.
     */
    function _handleUnleverage(
        uint256 amountLoan,
        bytes memory data
    ) internal override {
        (
            ,
            address user,
            uint256 positionId,
            address pendleSwap,
            SwapData memory swapData,
            LimitOrderData memory limitOrderData
        ) = abi.decode(
                data,
                (Action, address, uint256, address, SwapData, LimitOrderData)
            );

        LeveragePosition storage position = s_userLeveragePositions[user][
            positionId
        ];

        // Repay the loan, with flashloan amount, to withdraw position's total collateral
        _repayAndWithdrawCollateral(
            position.collateralToken,
            amountLoan,
            position.amountTotalCollateral,
            position.sharesBorrowed
        );

        // Swap withdrawn total collateral -> USDC
        uint256 amountSwappedLoanToken = _swapCollateralTokenToLoanToken(
            position.collateralToken,
            position.loanToken,
            position.amountTotalCollateral,
            pendleSwap,
            swapData,
            limitOrderData
        );

        // Repay the flash loan, with swapped USDC
        _forceApprove(position.loanToken, address(i_morpho), amountLoan);

        // And transfer out the remaining USDC to the user
        uint256 amountReturned;
        if (amountSwappedLoanToken > amountLoan) {
            amountReturned = amountSwappedLoanToken - amountLoan;
            _transferOut(position.loanToken, user, amountReturned);
        }

        emit LeveragePositionClosed(user, positionId, amountReturned);
    }

    /**
     * @notice Allows owner to add support for new collateral tokens.
     * @param configs Array of token configurations including swap and market parameters.
     *
     * Emits a {CollateralTokenAdded} event for each token added.
     */
    function addSupportedCollateralTokens(
        CollateralTokenConfig[] memory configs
    ) external onlyOwner {
        for (uint256 i = 0; i < configs.length; i++) {
            CollateralTokenConfig memory config = configs[i];

            _updateMorphoMarket(config.token, config.morphoMarketId);
            _updateSwapParams(
                config.token,
                SwapParams({
                    underlyingToken: config.underlyingToken,
                    pendleMarket: config.pendleMarket
                })
            );

            emit CollateralTokenAdded(
                config.token,
                config.pendleMarket,
                config.morphoMarketId
            );
        }
    }

    /////////////////////////
    // Public and External View Functions

    /**
     * @notice Calculates the maximum loan amount based on the user's collateral.
     * @param collateralToken The token used as collateral.
     * @param loanToken The stablecoin loan token (USDC).
     * @param userCollateralAmount Amount of collateral user is supplying.
     * @return amountToBorrow Amount of stablecoin that can be borrowed.
     *
     * @dev Assumes loanToken (USDC/Other stablecoins) are always valued at $1.
     */
    function calcLoanAmount(
        address collateralToken,
        address loanToken,
        uint256 userCollateralAmount
    ) public view returns (uint256) {
        uint256 userCollateralInUsd = getTokenUsdValue(
            collateralToken,
            userCollateralAmount
        );

        // Total position value in USD = collateralUsd / (1 - LTV)
        uint256 totalPositionUsd = userCollateralInUsd.divDown(
            Math.ONE - getMaxLtv(collateralToken)
        );

        // Loan amount = total position - collateral
        uint256 loanUsd = totalPositionUsd - userCollateralInUsd;

        // Adjust loan amount to match loanToken decimals
        return loanUsd.scaleTo(18, IERC20Metadata(loanToken).decimals());
    }

    /**
     * @notice Returns the USD value of a token amount.
     * @param token The address of the token.
     * @param amount Amount of token to value.
     * @return valueInUsd USD value (18 decimals).
     */
    function getTokenUsdValue(
        address token,
        uint256 amount
    ) public view returns (uint256) {
        return i_oracleRouter.getQuote(amount, token, USD);
    }

    /**
     * @notice Returns the maximum allowed loan-to-value ratio after applying liquidation buffer.
     * @param collateralToken Address of the collateral token.
     * @return maxLtv Adjusted loan-to-value ratio (scaled 1e18).
     */
    function getMaxLtv(address collateralToken) public view returns (uint256) {
        return s_marketParams[collateralToken].lltv - LIQUIDATION_BUFFER;
    }

    /**
     * @notice Returns all leverage positions for a specific user.
     * @param user The address of the user.
     * @return positions Array of leverage positions.
     */
    function getUserLeveragePositions(
        address user
    ) external view returns (LeveragePosition[] memory) {
        return s_userLeveragePositions[user];
    }

    /**
     * @notice Returns a single leverage position for a user.
     * @param user The address of the user.
     * @param positionId Index of the position.
     * @return position The leverage position details.
     */
    function getUserLeveragePosition(
        address user,
        uint256 positionId
    ) external view returns (LeveragePosition memory) {
        return s_userLeveragePositions[user][positionId];
    }
}
