// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

/// @title FlashLeverage
/// @notice Provides flashloan-based leveraged yields on stable PT-collateral (PENDLE) using morpho markets.
/// @dev Integrates with Morpho, Pendle, and custom SwapAggregator and MarketPositionmanager modules.
/// @dev Creates individual position proxy contracts for each user to isolate their positions.

import {MarketPositionManager, MarketParams, Id, UserProxy, IERC20Metadata, FLCError, Math} from "./MarketPositionManager.sol";
import {SwapAggregator, SwapData, LimitOrderData, ApproxParams} from "./SwapAggregator.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {LeverageParams, UnleverageParams} from "../structs/LeverageParams.sol";
import {CoreLeveragePosition} from "../structs/CoreLeveragePosition.sol";
import {CollateralTokenConfig} from "../structs/CollateralTokenConfig.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IPendleMarket} from "../../interfaces/IPendleMarket.sol";
import {IOracle} from "@morpho/interfaces/IOracle.sol";

contract FlashLeverageCore is
    MarketPositionManager,
    SwapAggregator,
    ReentrancyGuard,
    Ownable2Step,
    Pausable
{
    using Math for uint256;

    /////////////////////////
    // Constants and Immutables

    /// @notice Buffer subtracted from liquidation LTV to determine the max LTV (18 decimals)
    uint256 public constant LIQUIDATION_BUFFER = 25e15; // 2.5%

    /// @notice Maximum allowed change in final LTV after slippage (18 decimals)
    uint256 public constant SLIPPAGE_BUFFER = 1e16; // 1%

    /// @notice Implementation contract for user proxies
    address public immutable i_userProxyImplementation;

    /////////////////////////
    // Storage

    /// @notice Mapping to track authorized managers who can create and manage leverage positions.
    /// @dev Only addresses with manager status can call leverage and unleverage functions.
    /// Managers are exclusively used for fee and receipt token management
    mapping(address => bool) private s_managers;

    /// @notice Mapping from user => desiredLtv => proxy contract
    mapping(address user => mapping(uint256 desiredLtv => address proxyContract))
        public s_userProxies;

    /// @notice Nested mapping to store leverage positions for each user proxy, collateral token, and loan token combination.
    /// @dev Structure: userProxy => collateralToken => loanToken => CoreLeveragePosition
    mapping(address userProxy => mapping(address collateralToken => mapping(address loanToken => CoreLeveragePosition)))
        private s_positions;

    /////////////////////////
    // Modifiers

    /// @notice Ensures that only authorized managers can call the function.
    /// @dev Reverts with FlashLeverageCore__IsValidManager error if caller is not a manager.
    modifier onlyManager() {
        require(
            isManager(msg.sender),
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
            isSupportedCollateralToken(collateralToken, loanToken),
            FLCError.FlashLeverageCore__UnsupportedCollateralToken()
        );
        _;
    }

    /// @notice Validates that the provided amount is greater than zero.
    /// @dev Prevents operations with zero amounts which could lead to unexpected behavior.
    /// @param value The amount to validate.
    modifier validateAmountCollateral(uint256 value) {
        require(
            value > 0,
            FLCError.FlashLeverageCore__AmountCollateralCannotBeZero()
        );
        _;
    }

    /// @notice Validates that the provided amount is greater than zero.
    /// @dev Prevents operations with zero amounts which could lead to unexpected behavior.
    /// @param value The amount to validate.
    modifier validateSharesToBurn(uint256 value) {
        require(
            value > 0,
            FLCError.FlashLeverageCore__SharesToBurnCannotBeZero()
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
            desiredLtv <= getMaxLtv(collateralToken, loanToken),
            FLCError.FlashLeverageCore__ExceedsMaxLTV()
        );
        _;
    }

    /////////////////////////
    // Constructor

    /**
     * @notice Initializes the FlashLeverage contract.
     * @param morphoAddress Address of the Morpho protocol contract.
     * @param pendleRouter Address of the Pendle router for swap execution.
     */
    constructor(
        address morphoAddress,
        address pendleRouter
    )
        Ownable(msg.sender)
        SwapAggregator(pendleRouter)
        MarketPositionManager(morphoAddress)
    {
        if (morphoAddress == address(0) || pendleRouter == address(0)) {
            revert FLCError.FlashLeverageCore__CannotBeZeroAddress();
        }

        // Deploy the implementation contract to clone user proxies from
        i_userProxyImplementation = address(new UserProxy(address(this)));
    }

    /////////////////////////
    // External Functions

    /**
     * @notice Creates/Modifies leveraged positions by supplying stable PT-collateral and borrowing stablecoins via flashloan.
     * @param onBehalfOf The address of the user for whom the position is being created or modified.
     * @param params Struct containing leverage parameters including collateral, loan token, collateral amount, and other swap tokenConfigs.
     */
    function leverage(
        address onBehalfOf,
        LeverageParams calldata params
    )
        external
        onlyManager
        whenNotPaused
        validateCollateralToken(params.collateralToken, params.loanToken)
        validateAmountCollateral(params.amountCollateral)
        validateDesiredLtv(
            params.desiredLtv,
            params.collateralToken,
            params.loanToken
        )
    {
        address collateralToken = params.collateralToken;
        address loanToken = params.loanToken;
        uint256 amountCollateral = params.amountCollateral;

        _transferIn(collateralToken, msg.sender, amountCollateral);

        // FlashLoan Related
        uint256 amountFlashLoan = calcLeverageFlashLoan(
            params.desiredLtv,
            collateralToken,
            loanToken,
            amountCollateral
        );
        bytes memory data = abi.encode(
            Action.LEVERAGE,
            onBehalfOf, // user
            params.desiredLtv,
            collateralToken,
            loanToken,
            amountCollateral,
            params.approxParams,
            params.pendleSwap,
            params.tokenMintSy,
            params.minPtOut,
            params.swapData,
            params.limitOrderData
        );
        i_morpho.flashLoan(loanToken, amountFlashLoan, data);
    }

    /**
     * @notice Closes or reduces an existing leveraged position and returns the remaining amount (in loan token) to the user.
     * @param onBehalfOf The address of the user whose position is being unleveraged.
     * @param params Struct containing all parameters required to unwind leverage, including token addresses,
     * shares to burn, collateral withdrawal amount, and swap/limit order data.
     */
    function unleverage(
        address onBehalfOf,
        UnleverageParams calldata params
    )
        external
        onlyManager
        whenNotPaused
        validateSharesToBurn(params.sharesToBurn)
    {
        address collateralToken = params.collateralToken;
        address loanToken = params.loanToken;
        uint256 sharesToBurn = params.sharesToBurn;
        uint256 amountCollateralToWithdraw = params.amountCollateralToWithdraw;
        address userProxy = getUserProxy(onBehalfOf, params.desiredLtv);

        CoreLeveragePosition storage position = s_positions[userProxy][
            collateralToken
        ][loanToken];

        require(
            position.amountCollateral >= amountCollateralToWithdraw,
            FLCError.FlashLeverageCore__InsufficientCollateralToWithdraw()
        );
        require(
            position.sharesBorrowed >= sharesToBurn,
            FLCError.FlashLeverageCore__InsufficientSharesToBurn()
        );

        // Update the state
        unchecked {
            position.amountCollateral -= amountCollateralToWithdraw;
            position.sharesBorrowed -= sharesToBurn;
        }

        // Flash Loan Related
        uint256 amountFlashLoan = calcUnleverageFlashLoan(
            collateralToken,
            loanToken,
            sharesToBurn
        );
        bytes memory data = abi.encode(
            Action.UNLEVERAGE,
            msg.sender, // manager
            userProxy,
            collateralToken,
            loanToken,
            sharesToBurn,
            amountCollateralToWithdraw,
            params.pendleSwap,
            params.tokenRedeemSy,
            params.minTokenOut,
            params.swapData,
            params.limitOrderData
        );
        i_morpho.flashLoan(loanToken, amountFlashLoan, data);
    }

    /**
     * @notice Gets an existing user proxy or creates a new one for the specified user and desired LTV.
     * @dev Uses the clone factory pattern to create minimal proxy contracts for gas efficiency.
     * This function is permissionless and can be safely called by anyone.
     * @param user The address of the user to get or create a proxy for.
     * @param desiredLtv The desired loan-to-value ratio for this proxy.
     * @return proxy The address of the user's proxy contract.
     */
    function getOrCreateUserProxy(
        address user,
        uint256 desiredLtv
    ) public returns (address proxy) {
        proxy = s_userProxies[user][desiredLtv];

        if (proxy == address(0)) {
            proxy = Clones.clone(i_userProxyImplementation);
            s_userProxies[user][desiredLtv] = proxy;
        }

        return proxy;
    }

    /**
     * @notice Allows owner to add support for new collateral tokens.
     * @param tokenConfigs Array of token configurations including swap and market parameters.
     */
    function addSupportedCollateralTokens(
        CollateralTokenConfig[] calldata tokenConfigs
    ) external onlyOwner {
        for (uint256 i; i < tokenConfigs.length; ++i) {
            CollateralTokenConfig memory config = tokenConfigs[i];
            address collateralToken = config.collateralToken;

            require(
                collateralToken != address(0),
                FLCError.FlashLeverageCore__CannotBeZeroAddress()
            );

            (, address PT, ) = IPendleMarket(config.pendleMarket).readTokens();
            MarketParams memory marketParams = i_morpho.idToMarketParams(
                Id.wrap(config.morphoMarketId)
            );

            require(
                collateralToken == PT &&
                    collateralToken == marketParams.collateralToken,
                FLCError.FlashLeverageCore__InvalidCollateralToken()
            );

            require(
                IERC20Metadata(collateralToken).decimals() ==
                    Math.STANDARD_DECIMALS,
                FLCError.FlashLeverageCore__InvalidCollateralTokenDecimals()
            );

            _updateMarketParams(marketParams);
            _updatePendleMarket(collateralToken, config.pendleMarket);
        }
    }

    /**
     * @notice Sets manager status for a given address.
     * @dev Only the contract owner can modify manager permissions.
     * @param manager The address to add manager status for.
     */
    function addManager(address manager) external onlyOwner {
        if (!isManager(manager)) {
            s_managers[manager] = true;
        }
    }

    /**
     * @notice Pauses the contract, preventing leverage and unleverage operations.
     * @dev Can only be called by the contract owner. When paused, leverage and unleverage functions will revert.
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpauses the contract, allowing leverage and unleverage operations to resume.
     * @dev Can only be called by the contract owner.
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @notice Overrides renounceOwnership to prevent ownership renunciation.
     * @dev Intentionally disabled to retain upgradeability and collateral support management.
     */
    function renounceOwnership() public override(Ownable) {}

    /////////////////////////
    // Internal Functions

    /**
     * @notice Handles internal logic after flashloan is received for leveraging.
     * @dev Swaps borrowed tokens to PT-collateral, deposits the total PT-collateral,
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
            address user,
            uint256 desiredLtv,
            address collateralToken,
            address loanToken,
            uint256 amountCollateral,
            ApproxParams memory approxParams,
            address pendleSwap,
            address tokenMintSy,
            uint256 minPtOut,
            SwapData memory swapData,
            LimitOrderData memory limitOrderData
        ) = abi.decode(
                data,
                (
                    Action,
                    address,
                    uint256,
                    address,
                    address,
                    uint256,
                    ApproxParams,
                    address,
                    address,
                    uint256,
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
            tokenMintSy,
            minPtOut,
            swapData,
            limitOrderData
        );

        // Position's final collateral after leveraging
        uint256 amountLeveragedCollateral = amountCollateral +
            amountSwappedCollateral;

        // Revert if effective ltv is too high, accounting the slippage from swap
        _revertIfEffectiveLtvTooHigh(
            desiredLtv,
            collateralToken,
            loanToken,
            amountLeveragedCollateral,
            amountLoan
        );

        // Supply total collateral and borrow loan token
        address userProxy = getOrCreateUserProxy(user, desiredLtv);
        uint256 sharesBorrowed = _supplyCollateralAndBorrowViaProxy(
            userProxy,
            collateralToken,
            loanToken,
            amountLeveragedCollateral,
            amountLoan
        );

        // Update the position state
        CoreLeveragePosition storage position = s_positions[userProxy][
            collateralToken
        ][loanToken];
        position.amountCollateral += amountLeveragedCollateral;
        position.sharesBorrowed += sharesBorrowed;

        // Repay the flash loan, with borrowed loan token
        _forceApprove(loanToken, address(i_morpho), amountLoan);
    }

    /**
     * @notice Handles internal logic after flashloan is received for unleveraging.
     * @dev Repays existing borrow, withdraws PT-collateral, swaps it to the loan token(stablecoin),
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
            address userProxy,
            address collateralToken,
            address loanToken,
            uint256 sharesToBurn,
            uint256 amountCollateralToWithdraw,
            address pendleSwap,
            address tokenRedeemSy,
            uint256 minTokenOut,
            SwapData memory swapData,
            LimitOrderData memory limitOrderData
        ) = abi.decode(
                data,
                (
                    Action,
                    address,
                    address,
                    address,
                    address,
                    uint256,
                    uint256,
                    address,
                    address,
                    uint256,
                    SwapData,
                    LimitOrderData
                )
            );

        // Reduce the position's existing loan, with the flashloan, to withdraw position's required collateral
        _repayAndWithdrawCollateralViaProxy(
            userProxy,
            collateralToken,
            loanToken,
            amountLoan,
            amountCollateralToWithdraw,
            sharesToBurn
        );

        // This would only make the positions LTV better
        if (amountCollateralToWithdraw == 0) {
            return;
        }

        // Swap withdrawn collateral -> loan token
        uint256 amountSwappedLoanToken = _swapCollateralTokenToLoanToken(
            collateralToken,
            loanToken,
            amountCollateralToWithdraw,
            pendleSwap,
            tokenRedeemSy,
            minTokenOut,
            swapData,
            limitOrderData
        );

        // Repay the flash loan, with swapped loan token
        _forceApprove(loanToken, address(i_morpho), amountLoan);

        // And transfer out the remaining loan Token to the manager
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
     * @param amountLoan Amount Loan in loan token decimals
     */
    function _revertIfEffectiveLtvTooHigh(
        uint256 desiredLtv,
        address collateralToken,
        address loanToken,
        uint256 amountCollateral,
        uint256 amountLoan
    ) internal view {
        uint256 amountCollateralInLoanToken = getCollateralValueInLoanToken(
            collateralToken,
            loanToken,
            amountCollateral
        );

        amountLoan = amountLoan.scaleTo(
            s_loanTokenDecimals[loanToken],
            Math.STANDARD_DECIMALS
        );

        uint256 effectiveLtv = amountLoan.divDown(amountCollateralInLoanToken);

        require(
            effectiveLtv <= desiredLtv + SLIPPAGE_BUFFER,
            FLCError.FlashLeverageCore__EffectiveLtvTooHigh(
                desiredLtv,
                effectiveLtv
            )
        );
    }

    /////////////////////////
    // Public and External View Functions

    /**
     * @notice Checks if an address has manager privileges
     * @param manager The address to check for manager status
     * @return bool True if the address is a registered manager, false otherwise
     * @dev Uses the s_managers mapping to determine manager status. Managers typically have
     *      elevated permissions for administrative functions.
     */
    function isManager(address manager) public view returns (bool) {
        return s_managers[manager];
    }

    /**
     * @notice Checks if a collateral-loan token pair is supported for leverage operations
     * @param collateralToken The address of the collateral token to validate
     * @param loanToken The address of the loan token to validate
     * @return bool True if the token pair is supported, false otherwise
     * @dev Validates support by checking if market parameters exist for the token pair.
     *      A non-zero collateralToken address in the market parameters indicates the pair
     *      has been configured and is available for leverage operations.
     */
    function isSupportedCollateralToken(
        address collateralToken,
        address loanToken
    ) public view returns (bool) {
        return
            s_marketParams[collateralToken][loanToken].collateralToken !=
            address(0);
    }

    /**
     * @notice Returns the liquidation loan-to-value ratio for a given collateral-loan token pair.
     * @dev This is the maximum LTV before a position becomes liquidatable.
     * @param collateralToken Address of the collateral token.
     * @param loanToken Address of the loan token.
     * @return liqLtv Liquidation loan-to-value ratio (18 decimals).
     */
    function getLiqLtv(
        address collateralToken,
        address loanToken
    ) public view returns (uint256) {
        return s_marketParams[collateralToken][loanToken].lltv;
    }

    /**
     * @notice Returns the max loan-to-value ratio after applying the liquidation buffer.
     * @param collateralToken Address of the collateral token.
     * @param loanToken Address of the loan token.
     * @return maxLtv Max loan-to-value ratio (18 decimals).
     */
    function getMaxLtv(
        address collateralToken,
        address loanToken
    ) public view returns (uint256) {
        return getLiqLtv(collateralToken, loanToken) - LIQUIDATION_BUFFER;
    }

    /**
     * @notice Returns the loan token value of a collateral token amount.
     * @param collateralToken Address of the CollateralToken.
     * @param loanToken Address of the Loan Token.
     * @param amountCollateral Amount of collateral token to value.
     * @return Value of collateral amount in loan token (Unscaled to only 18 decimals for standardisation in calculations).
     */
    function getCollateralValueInLoanToken(
        address collateralToken,
        address loanToken,
        uint256 amountCollateral
    ) public view returns (uint256) {
        IOracle oracle = IOracle(
            s_marketParams[collateralToken][loanToken].oracle
        );

        uint256 scalePrice = oracle.price();
        uint256 totalValue = amountCollateral.mulDown(scalePrice);

        return
            totalValue.scaleTo(
                Math.STANDARD_DECIMALS + s_loanTokenDecimals[loanToken],
                Math.STANDARD_DECIMALS
            );
    }

    /**
     * @notice Calculates the flashloan amount needed for leveraging based on desired LTV and collateral amount.
     * @param desiredLtv The desired loan-to-value ratio for the position.
     * @param collateralToken The token used as collateral.
     * @param loanToken The stablecoin loan token (eg: USDC, DAI, USR, ...).
     * @param amountCollateral Amount of collateral being supplied.
     * @return amountToBorrow Amount of loanToken that can be borrowed (scaled to loanToken decimals).
     */
    function calcLeverageFlashLoan(
        uint256 desiredLtv,
        address collateralToken,
        address loanToken,
        uint256 amountCollateral
    ) public view returns (uint256) {
        uint256 collateralValue = getCollateralValueInLoanToken(
            collateralToken,
            loanToken,
            amountCollateral
        );

        // Total position value = collateralValue / (1 - LTV)
        uint256 totalPositionValue = collateralValue.divDown(
            Math.ONE - desiredLtv
        );

        // Loan amount = total position - collateral
        uint256 amountLoan = totalPositionValue - collateralValue;

        return
            amountLoan.scaleTo(
                Math.STANDARD_DECIMALS,
                s_loanTokenDecimals[loanToken]
            );
    }

    /**
     * @notice Calculates the flashloan amount needed for unleveraging based on shares to burn.
     * @param collateralToken The token used as collateral.
     * @param loanToken The stablecoin loan token (eg: USDC, DAI, USR, ...).
     * @param sharesToBurn Shares to be burned during unleveraging.
     * @return amountToBorrow Amount of loanToken needed for flashloan (scaled to loanToken decimals).
     */
    function calcUnleverageFlashLoan(
        address collateralToken,
        address loanToken,
        uint256 sharesToBurn
    ) public view returns (uint256) {
        return
            getSharesValueInLoanToken(collateralToken, loanToken, sharesToBurn)
                .scaleTo(
                    Math.STANDARD_DECIMALS,
                    s_loanTokenDecimals[loanToken]
                );
    }

    /**
     * @notice Returns the core leverage position of a user for a given collateral and loan token pair.
     * @param user The address of the user.
     * @param desiredLtv The desired loan-to-value ratio for the position.
     * @param collateralToken The address of the collateral token used in the leverage position.
     * @param loanToken The address of the token borrowed in the core leverage position.
     * @return position The user's core leverage position including collateral amount and borrowed shares.
     */
    function getUserCoreLeveragePosition(
        address user,
        uint256 desiredLtv,
        address collateralToken,
        address loanToken
    ) public view returns (CoreLeveragePosition memory) {
        address userProxy = getUserProxy(user, desiredLtv);
        return s_positions[userProxy][collateralToken][loanToken];
    }

    /**
     * @notice Returns the proxy contract address for a specific user and desired LTV.
     * @param user The address of the user.
     * @param desiredLtv The desired loan-to-value ratio.
     * @return The address of the user's proxy contract, or address(0) if none exists.
     */
    function getUserProxy(
        address user,
        uint256 desiredLtv
    ) public view returns (address) {
        return s_userProxies[user][desiredLtv];
    }
}
