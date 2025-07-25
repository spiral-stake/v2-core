// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

/// @title FlashLeverage
/// @notice Provides flashloan-based leveraged yields on stable PT-collateral (PENDLE) using morpho markets.
/// @dev Integrates with Morpho, Pendle, and custom SwapAggregator and MarketPositionmanager modules.

import {IFlashLeverageCore, CoreLeveragePosition} from "../../interfaces/IFlashLeverageCore.sol";
import {SwapAggregator, CollateralTokenData, SwapData, LimitOrderData, ApproxParams} from "./SwapAggregator.sol";
import {MarketPositionManager, MarketParams, Id} from "./MarketPositionManager.sol";
import {LeverageParams, UnleverageParams} from "../structs/LeverageParams.sol";
import {CollateralTokenConfig} from "../structs/CollateralTokenConfig.sol";
import {IOracleRouter} from "../../interfaces/IOracleRouter.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import {Math} from "../libraries/Math.sol";
import {FLCError} from "../libraries/Error.sol";

contract FlashLeverageCore is
    IFlashLeverageCore,
    MarketPositionManager,
    SwapAggregator,
    ReentrancyGuard,
    Ownable2Step
{
    using Math for uint256;

    /////////////////////////
    // Constants and Immutables

    /// @notice USD reference address used in price feeds (e.g., Chainlink).
    address private constant USD = 0x0000000000000000000000000000000000000348;

    /// @notice Buffer (5%) subtracted from liquidation LTV to determine the max LTV.
    uint256 private constant LIQUIDATION_BUFFER = 5e16;

    /// @notice Maximum allowed slippage (1% = 1e16)
    uint256 private constant SLIPPAGE_BUFFER = 1e16;

    /// @notice Oracle router used for fetching USD price quotes.
    IOracleRouter private immutable i_oracleRouter;

    /////////////////////////
    // Storage

    /// @notice Mapping to track authorized managers who can create and manage leverage positions.
    /// @dev Only addresses with manager status can call leverage and unleverage functions.
    /// Managers are exclusively used for fee and receipt token management
    mapping(address => bool) private s_managers;

    /// @notice Nested mapping to store leverage positions for each manager, collateral token, and loan token combination.
    /// @dev Structure: manager => collateralToken => loanToken => CoreLeveragePosition
    mapping(address manager => mapping(address collateralToken => mapping(address loanToken => CoreLeveragePosition)))
        private s_leveragePositions;

    /////////////////////////
    // Modifiers

    /// @notice Ensures that only authorized managers can call the function.
    /// @dev Reverts with FlashLeverageCore__IsValidManager error if caller is not a manager.
    modifier isManager() {
        require(
            s_managers[msg.sender],
            FLCError.FlashLeverageCore__NotAManager()
        );
        _;
    }

    /// @notice Validates that the collateral token is supported for leveraging.
    /// @dev Checks if a market exists for the collateral-loan token pair.
    /// @param collateralToken The address of the collateral token to validate.
    /// @param loanToken The address of the loan token to validate against.
    modifier validateCollateralToken(
        address collateralToken,
        address loanToken
    ) {
        require(
            s_marketParams[collateralToken][loanToken].collateralToken !=
                address(0),
            FLCError.FlashLeverageCore__UnsupportedCollateralToken()
        );
        _;
    }

    /// @notice Validates that the provided amount is greater than zero.
    /// @dev Prevents operations with zero amounts which could lead to unexpected behavior.
    /// @param value The amount to validate.
    modifier validateAmount(uint256 value) {
        require(value > 0, FLCError.FlashLeverageCore__AmountCannotBeZero());
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
     * @notice Creates/Modifies manager's leveraged positions by supplying stable PT-collateral and borrowing stablecoins via flashloan.
     * @param params Struct containing leverage parameters including collateral, loan token, collateral amount, and other swap configs.
     */
    function leverage(
        LeverageParams calldata params
    )
        external
        isManager
        validateCollateralToken(params.collateralToken, params.loanToken)
        validateAmount(params.amountCollateral)
    {
        address manager = msg.sender;
        address collateralToken = params.collateralToken;
        address loanToken = params.loanToken;
        uint256 amountCollateral = params.amountCollateral;

        _transferIn(collateralToken, manager, amountCollateral);

        // FlashLoan Related
        uint256 amountFlashLoan = calcFlashLoanAmount(
            collateralToken,
            loanToken,
            amountCollateral
        );
        bytes memory data = abi.encode(
            Action.LEVERAGE,
            manager,
            collateralToken,
            loanToken,
            amountCollateral,
            params.approxParams,
            params.pendleSwap,
            params.swapData,
            params.limitOrderData
        );
        i_morpho.flashLoan(loanToken, amountFlashLoan, data);
    }

    /**
     * @notice Closes or reduces an existing leveraged position and returns the remaining amount (in loan token) to the position owner.
     * @param params Struct containing all parameters required to unwind leverage, including token addresses,
     * shares to burn, collateral withdrawal amount, and swap/limit order data.
     */
    function unleverage(
        UnleverageParams calldata params
    )
        external
        isManager
        validateAmount(params.sharesToBurn)
        validateAmount(params.amountCollateralToWithdraw)
    {
        address manager = msg.sender;
        address collateralToken = params.collateralToken;
        address loanToken = params.loanToken;
        uint256 sharesToBurn = params.sharesToBurn;
        uint256 amountCollateralToWithdraw = params.amountCollateralToWithdraw;

        CoreLeveragePosition storage position = s_leveragePositions[manager][
            collateralToken
        ][loanToken];

        require(
            position.sharesBorrowed >= sharesToBurn,
            FLCError.FlashLeverageCore__InsufficientSharesBorrowed()
        );
        require(
            position.amountCollateral >= amountCollateralToWithdraw,
            FLCError.FlashLeverageCore__InsufficientCollateralDeposited()
        );

        // Update the state
        unchecked {
            position.amountCollateral -= amountCollateralToWithdraw;
            position.sharesBorrowed -= sharesToBurn;
        }

        _revertIfExceedsMaxLtv(
            collateralToken,
            loanToken,
            position.amountCollateral,
            getSharesToAsset(
                collateralToken,
                loanToken,
                position.sharesBorrowed
            )
        );

        // Flash Loan Related
        uint256 amountFlashLoan = getSharesToAsset(
            collateralToken,
            loanToken,
            sharesToBurn
        );
        bytes memory data = abi.encode(
            Action.UNLEVERAGE,
            manager,
            collateralToken,
            loanToken,
            sharesToBurn,
            amountCollateralToWithdraw,
            params.pendleSwap,
            params.swapData,
            params.limitOrderData
        );
        i_morpho.flashLoan(loanToken, amountFlashLoan, data);
    }

    /**
     * @notice Allows owner to add support for new collateral tokens.
     * @param configs Array of token configurations including swap and market parameters.
     */
    function addSupportedCollateralTokens(
        CollateralTokenConfig[] calldata configs
    ) external onlyOwner {
        uint256 configsLength = configs.length;
        for (uint256 i = 0; i < configsLength; ++i) {
            CollateralTokenConfig memory config = configs[i];

            require(config.collateralToken != address(0));
            require(config.loanToken != address(0));
            require(config.underlyingToken != address(0));
            require(config.morphoMarketId != bytes32(0));
            require(config.pendleMarket != address(0));

            _updateMorphoMarket(
                config.collateralToken,
                config.loanToken,
                config.morphoMarketId
            );
            _updateCollateralTokenData(
                config.collateralToken,
                CollateralTokenData({
                    underlyingToken: config.underlyingToken,
                    pendleMarket: config.pendleMarket
                })
            );
        }
    }

    /**
     * @notice Sets or revokes manager status for a given address.
     * @dev Only the contract owner can modify manager permissions.
     * @param manager The address to set manager status for.
     * @param value True to grant manager status, false to revoke it.
     */
    function setManager(address manager, bool value) external onlyOwner {
        s_managers[manager] = value;
    }

    /**
     * @notice Overrides renounceOwnership to prevent ownership renunciation.
     * @dev Intentionally disabled to retain upgradeability and collateral support management.
     */
    function renounceOwnership() public pure override {
        revert FLCError.FlashLeverageCore__RenounceOwnershipDisabled();
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
        bytes calldata data
    ) internal override nonReentrant {
        (
            ,
            address manager,
            address collateralToken,
            address loanToken,
            uint256 amountCollateral,
            ApproxParams memory approxParams,
            address pendleSwap,
            SwapData memory swapData,
            LimitOrderData memory limitOrderData
        ) = abi.decode(
                data,
                (
                    Action,
                    address,
                    address,
                    address,
                    uint256,
                    ApproxParams,
                    address,
                    SwapData,
                    LimitOrderData
                )
            );

        // Swap amount loan -> PT collateral
        uint256 amountSwappedCollateral = _swapLoanTokenToCollateralToken(
            loanToken,
            collateralToken,
            amountLoan,
            approxParams,
            pendleSwap,
            swapData,
            limitOrderData
        );

        // Position's final collateral after leveraging
        uint256 amountLeveragedCollateral = amountCollateral +
            amountSwappedCollateral;

        // Check if it exceeds max LTV for a leverage
        _revertIfExceedsMaxLtv(
            collateralToken,
            loanToken,
            amountLeveragedCollateral,
            amountLoan
        );

        // Supply total collateral and borrow loan token
        uint256 sharesBorrowed = _supplyCollateralAndBorrow(
            collateralToken,
            loanToken,
            amountLeveragedCollateral,
            amountLoan
        );

        // Update the state
        CoreLeveragePosition storage position = s_leveragePositions[manager][
            collateralToken
        ][loanToken];
        position.amountCollateral += amountLeveragedCollateral;
        position.sharesBorrowed += sharesBorrowed;

        // Repay the flash loan, with borrowed loan token
        _forceApprove(loanToken, address(i_morpho), amountLoan);
    }

    /**
     * @dev Handles internal logic after flashloan is received for unleveraging.
     *      Repays existing borrow, withdraws PT-collateral, swaps it to the loan token(stablecoin),
     *      repays the flashloan, and returns excess (initial + leveraged yield)
     * @param amountLoan Amount borrowed via flashloan for debt repayment.
     * @param data Encoded unleverage action data.
     */
    function _handleUnleverage(
        uint256 amountLoan,
        bytes calldata data
    ) internal override nonReentrant {
        (
            ,
            address manager,
            address collateralToken,
            address loanToken,
            uint256 sharesToBurn,
            uint256 amountCollateralToWithdraw,
            address pendleSwap,
            SwapData memory swapData,
            LimitOrderData memory limitOrderData
        ) = abi.decode(
                data,
                (
                    Action,
                    address,
                    address,
                    address,
                    uint256,
                    uint256,
                    address,
                    SwapData,
                    LimitOrderData
                )
            );

        // Reduce the position's existing loan, with the flashloan, to withdraw position's required collateral
        _repayAndWithdrawCollateral(
            collateralToken,
            loanToken,
            amountLoan,
            amountCollateralToWithdraw,
            sharesToBurn
        );

        // Swap withdrawn collateral -> loan token
        uint256 amountSwappedLoanToken = _swapCollateralTokenToLoanToken(
            collateralToken,
            loanToken,
            amountCollateralToWithdraw,
            pendleSwap,
            swapData,
            limitOrderData
        );

        // Repay the flash loan, with swapped loan token
        _forceApprove(loanToken, address(i_morpho), amountLoan);

        // And transfer out the remaining loan Token to the core leveraga position manager
        uint256 amountReturned;
        if (amountSwappedLoanToken > amountLoan) {
            unchecked {
                amountReturned = amountSwappedLoanToken - amountLoan;
            }
            _transferOut(loanToken, manager, amountReturned);
        }
    }

    /**
     * @dev Validates that the actual LTV after leverage/unleverage doesn't exceed the max LTV.
     * @param collateralToken Address of the collateral token.
     * @param loanToken Address of the loan token.
     * @param amountCollateral Total amount of collateral after leverage/unleverage.
     * @param amountLoan Amount borrowed
     */
    function _revertIfExceedsMaxLtv(
        address collateralToken,
        address loanToken,
        uint256 amountCollateral,
        uint256 amountLoan
    ) internal view {
        uint256 amountCollateralInUsd = getTokenUsdValue(
            collateralToken,
            amountCollateral
        );

        if (amountLoan == 0) {
            return;
        }

        uint256 effectiveLtv = amountLoan.divDown(amountCollateralInUsd);

        require(
            effectiveLtv <= getMaxLtv(collateralToken, loanToken),
            FLCError.FlashLeverageCore__ExceedsMaxLTV()
        );
    }

    /////////////////////////
    // Public and External View Functions

    /**
     * @notice Calculates the maximum loan amount based on the amount collateral and safe LTV.
     * @param collateralToken The token used as collateral.
     * @param loanToken The stablecoin loan token (eg: USDC, DAI, USR, ...).
     * @param amountCollateral Amount of collateral is being supplied.
     * @return amountToBorrow Amount of stablecoin that can be borrowed.
     *
     * @dev Assumes loanToken (morpho supported stablecoins) are always valued at $1.
     */
    function calcFlashLoanAmount(
        address collateralToken,
        address loanToken,
        uint256 amountCollateral
    ) public view returns (uint256) {
        uint256 amountCollateralInUsd = getTokenUsdValue(
            collateralToken,
            amountCollateral
        );

        // Total position value in USD = collateralUsd / (1 - LTV)
        uint256 totalPositionUsd = amountCollateralInUsd.divDown(
            Math.ONE - getSafeLtv(collateralToken, loanToken)
        );

        // Loan amount = total position - collateral
        uint256 loanUsd = totalPositionUsd - amountCollateralInUsd;

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

    /// @notice Returns the safe LTV used for leverage calculations after applying liquidation and slippage buffer.
    /// @param collateralToken Address of the collateral token.
    /// @param loanToken Address of the loan token.
    /// @return safeLtv Safe loan-to-value ratio (scaled 1e18).
    function getSafeLtv(
        address collateralToken,
        address loanToken
    ) public view returns (uint256) {
        return getMaxLtv(collateralToken, loanToken) - SLIPPAGE_BUFFER;
    }

    /**
     * @notice Returns the max loan-to-value ratio after applying the liquidation buffer.
     * @param collateralToken Address of the collateral token.
     * @param loanToken Address of the loan token.
     * @return maxLtv Max loan-to-value ratio (scaled 1e18).
     */
    function getMaxLtv(
        address collateralToken,
        address loanToken
    ) public view returns (uint256) {
        return getLiqLtv(collateralToken, loanToken) - LIQUIDATION_BUFFER;
    }

    /**
     * @notice Returns the liquidation loan-to-value ratio for a given collateral-loan token pair.
     * @dev This is the maximum LTV before a position becomes liquidatable.
     * @param collateralToken Address of the collateral token.
     * @param loanToken Address of the loan token.
     * @return liqLtv Liquidation loan-to-value ratio (scaled 1e18).
     */
    function getLiqLtv(
        address collateralToken,
        address loanToken
    ) public view returns (uint256) {
        return s_marketParams[collateralToken][loanToken].lltv;
    }

    /**
     * @notice Returns the core leverage position of a manager for a given collateral and loan token pair.
     * @param manager The address of the manager.
     * @param collateralToken The address of the collateral token used in the leverage position.
     * @param loanToken The address of the token borrowed in the core leverage position.
     * @return position The manager's core leverage position including collateral amount and borrowed shares.
     */
    function getCoreLeveragePosition(
        address manager,
        address collateralToken,
        address loanToken
    ) public view returns (CoreLeveragePosition memory) {
        return s_leveragePositions[manager][collateralToken][loanToken];
    }
}
