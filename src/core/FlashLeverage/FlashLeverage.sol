// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

/// @notice FlashLeverage
/// @notice Provide flash loan based leveraged yields on yield bearing tokens using morpho markets
/// @dev Integrates with custom SwapAggregator and MarketPositionManager modules.
/// @dev Creates individual position proxy contracts for each user to isolate their positions.

import {MarketPositionManager, MarketParams, Id, UserProxy, IERC20Metadata, FLError, Math} from "./MarketPositionManager.sol";
import {SwapManager} from "./SwapManager.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {LeverageParams} from "../structs/LeverageParams.sol";
import {SwapParams} from "../structs/SwapParams.sol";
import {LeveragePosition} from "../structs/LeveragePosition.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {IOracle} from "@morpho/interfaces/IOracle.sol";

import {console} from "forge-std/console.sol";

contract FlashLeverage is
    MarketPositionManager,
    SwapManager,
    ReentrancyGuard,
    Ownable2Step
{
    using Math for uint256;

    /////////////////////////
    // Constants and Immutables

    /// @notice Buffer subtracted from liquidation LTV to determine the max LTV (18 decimals)
    uint256 public constant LIQUIDATION_BUFFER = 25e15; // 2.5%

    /// @notice Maximum allowed change in effective LTV after slippage from the swap (18 decimals)
    uint256 public constant SLIPPAGE_BUFFER = 1e16; // 1%

    /// @notice Max Fee percentage in basis points (10%)
    uint256 private constant MAX_YIELD_FEE = 10e16;

    /// @notice Implementation contract for creating individual user proxies
    address public immutable i_userProxyImplementation;

    /////////////////////////
    // Storage

    mapping(address user => LeveragePosition[]) private s_userLeveragePositions;

    /// @notice Treasury address to receive fees
    address private s_treasury;

    /// @notice Performance based yield fees on the effective yield generated
    uint256 private s_yieldFee;

    /// @notice Flag to enable user direct control of their proxies
    bool public recoveryMode;

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
            FLError.FlashLeverage__CannotBeZeroAddress()
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
            FLError.FlashLeverage__UnsupportedCollateralToken()
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
            FLError.FlashLeverage__ExceedsMaxLTV()
        );
        _;
    }

    /**
     * @notice Initializes the FlashLeverage contract.
     * @param morphoAddress Address of the Morpho protocol contract.
     * @param swapRouter Address of the Pendle router for swap execution.
     */
    constructor(
        address morphoAddress,
        address swapRouter,
        address treasury
    )
        Ownable(msg.sender)
        MarketPositionManager(morphoAddress)
        SwapManager(swapRouter)
    {
        if (morphoAddress == address(0) || swapRouter == address(0)) {
            revert FLError.FlashLeverage__CannotBeZeroAddress();
        }

        // Deploy the implementation contract to clone user proxies from
        i_userProxyImplementation = address(
            new UserProxy(address(this), morphoAddress)
        );

        s_treasury = treasury;
        s_yieldFee = MAX_YIELD_FEE;
    }

    /////////////////////////
    // External Functions

    function swapAndLeverage(
        address onBehalfOf,
        SwapParams calldata swapParams,
        LeverageParams calldata params
    )
        external
        validateOnBehalfOf(onBehalfOf)
        validateDesiredLtv(
            params.desiredLtv,
            params.collateralToken,
            params.loanToken
        )
        validateCollateralToken(params.collateralToken, params.loanToken)
        validateAmount(params.amountCollateral)
    {
        _transferIn(swapParams.tokenIn, msg.sender, swapParams.amountIn);
        _swap(swapParams.tokenIn, swapParams.amountIn, swapParams.swapData);
        _transferBackRemaining(
            params.collateralToken,
            _selfBalance(params.collateralToken),
            params.amountCollateral
        );

        _leverage(onBehalfOf, params);
    }

    function leverage(
        address onBehalfOf,
        LeverageParams calldata params
    )
        external
        validateOnBehalfOf(onBehalfOf)
        validateDesiredLtv(
            params.desiredLtv,
            params.collateralToken,
            params.loanToken
        )
        validateCollateralToken(params.collateralToken, params.loanToken)
        validateAmount(params.amountCollateral)
    {
        _transferIn(
            params.collateralToken,
            msg.sender,
            params.amountCollateral
        );

        _leverage(onBehalfOf, params);
    }

    /**
     * @notice Creates leveraged positions by supplying collateraToken and borrowing via flashloan.
     * @param onBehalfOf The address of the user for whom the position is being created for.
     * @param params Struct containing leverage parameters including collateral, loan token, collateral amount, and other swap tokenConfigs.
     * @dev It is a internal function
     */
    function _leverage(
        address onBehalfOf,
        LeverageParams calldata params
    ) internal {
        address collateralToken = params.collateralToken;
        address loanToken = params.loanToken;
        uint256 amountCollateral = params.amountCollateral;

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
            params.swapData
        );
        i_morpho.flashLoan(loanToken, amountFlashLoan, data);
    }

    /**
     * @notice Closes an existing leveraged position and returns the final amount (in loan token) to the user.
     * @dev Only the leverage position's owner can call this function
     */
    function deleverage(uint256 positionId, bytes memory swapData) external {
        LeveragePosition storage position = s_userLeveragePositions[msg.sender][
            positionId
        ];

        // Closing the position
        position.open = false;

        // Flash Loan Related
        uint256 amountFlashLoan = calcUnleverageFlashLoan(
            position.collateralToken,
            position.loanToken,
            position.sharesBorrowed
        );
        bytes memory data = abi.encode(
            Action.UNLEVERAGE,
            msg.sender,
            positionId,
            swapData
        );
        i_morpho.flashLoan(position.loanToken, amountFlashLoan, data);
    }

    /**
     * @notice Creates a new user proxy for each position that user creates
     * @dev Uses the clone factory pattern to create minimal proxy contracts for gas efficiency.
     * This function is permissionless and can be safely called by anyone.
     * @param user The address of the user to get or create a proxy for.
     * @return proxy The address of the user's proxy contract.
     */
    function createUserProxy(address user) public returns (address proxy) {
        proxy = Clones.clone(i_userProxyImplementation);
        UserProxy(proxy).initialize(user);
    }

    /**
     * @notice Allows owner to add support for new collateral tokens.
     * @param collateralToken Address of the collateralToken to be leveraged
     * @param morphoMarketId Address of the morphoMarketId for the collateralToken
     */
    function addSupportedCollateralToken(
        address collateralToken,
        bytes32 morphoMarketId
    ) external onlyOwner {
        // Zero Address check
        require(
            collateralToken != address(0),
            FLError.FlashLeverage__CannotBeZeroAddress()
        );

        // Morpho market check
        MarketParams memory marketParams = i_morpho.idToMarketParams(
            Id.wrap(morphoMarketId)
        );
        require(
            collateralToken == marketParams.collateralToken,
            FLError.FlashLeverage__InvalidCollateralToken()
        );

        // Token Decimal check (only tokens with 18 decimals)
        require(
            IERC20Metadata(collateralToken).decimals() ==
                Math.STANDARD_DECIMALS,
            FLError.FlashLeverage__InvalidCollateralTokenDecimals()
        );

        _updateMarketParams(marketParams);
    }

    /**
     * @notice Updates the treasury address
     * @param newTreasury The new treasury address
     * @dev Only callable by the contract owner. Validates that the new treasury is not zero address.
     */
    function updateTreasury(address newTreasury) external onlyOwner {
        require(
            newTreasury != address(0),
            FLError.FlashLeverage__CannotBeZeroAddress()
        );

        s_treasury = newTreasury;
    }

    /**
     * @notice Updates the protocol yield fee.
     * @param newYieldFee The new yield fee to be set in basis points of 1e18 precision.
     * @dev Can only be called by the contract owner.
     *      Reverts if the new fee is zero or exceeds `MAX_YIELD_FEE`.
     */
    function updateYieldFee(uint256 newYieldFee) external onlyOwner {
        require(
            newYieldFee != 0 && newYieldFee <= MAX_YIELD_FEE,
            FLError.FlashLeverage__InvalidYieldFee()
        );

        s_yieldFee = newYieldFee;
    }

    /**
     * @notice Recovers any ERC20 tokens accidentally sent to this contract
     * @param token The address of the token to recover
     */
    function recover(address token) external onlyOwner {
        _transferOut(token, msg.sender, _selfBalance(token));
    }

    /// @notice onlyOwner
    function setRecoveryMode(bool _enabled) external onlyOwner {
        recoveryMode = _enabled;
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
     * @dev Swaps borrowed tokens to the collateral token, deposits the total collateral,
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
            bytes memory swapData
        ) = abi.decode(
                data,
                (Action, address, uint256, address, address, uint256, bytes)
            );

        // Swap amount loan -> PT collateral
        uint256 amountSwappedCollateral = _swap(
            loanToken,
            amountLoan,
            swapData
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
        address userProxy = createUserProxy(user);
        uint256 sharesBorrowed = _supplyCollateralAndBorrowViaProxy(
            userProxy,
            collateralToken,
            loanToken,
            amountLeveragedCollateral,
            amountLoan
        );

        // Repay the flash loan, with borrowed loan token
        _forceApprove(loanToken, address(i_morpho), amountLoan);

        // Position Tracking Related: Amount Collateral Deposited in loan token
        uint256 amountCollateralInLoanToken = _getAmountCollateralInLoanToken(
            collateralToken,
            loanToken,
            amountCollateral
        );

        // Add new Leverage Position for user
        uint256 positionId = s_userLeveragePositions[user].length;
        s_userLeveragePositions[user].push(
            LeveragePosition({
                open: true,
                collateralToken: collateralToken,
                loanToken: loanToken,
                amountCollateral: amountCollateral,
                amountLeveragedCollateral: amountLeveragedCollateral,
                sharesBorrowed: sharesBorrowed,
                userProxy: userProxy,
                amountCollateralInLoanToken: amountCollateralInLoanToken
            })
        );

        emit LeveragePositionOpened(
            user,
            positionId,
            amountCollateralInLoanToken
        );
    }

    /**
     * @notice Handles internal logic after flashloan is received for deleveraging.
     * @dev Repays existing borrow, withdraws collateral, swaps it to the loan token,
     *      repays the flashloan, and returns excess (initial collateral + leveraged yield)
     * @param amountLoan Amount borrowed via flashloan for debt repayment.
     * @param data Encoded unleverage action data.
     */
    function _handleDeleverage(
        uint256 amountLoan,
        bytes calldata data
    ) internal override nonReentrant returns (uint256 userAmountReturned) {
        (, address user, uint256 positionId, bytes memory swapData) = abi
            .decode(data, (Action, address, uint256, bytes));

        LeveragePosition memory position = getUserLeveragePosition(
            user,
            positionId
        );

        // Close the position's existing loan, with the flashloan, to withdraw position's required collateral
        _repayAndWithdrawCollateralViaProxy(
            position.userProxy,
            position.collateralToken,
            position.loanToken,
            amountLoan,
            position.amountLeveragedCollateral,
            position.sharesBorrowed
        );

        // Swap withdrawn collateral -> loan token
        uint256 amountSwappedLoanToken = _swap(
            position.collateralToken,
            position.amountLeveragedCollateral,
            swapData
        );

        // Repay the flash loan, with swapped loan token
        _forceApprove(position.loanToken, address(i_morpho), amountLoan);

        uint256 totalAmountReturned;
        if (amountSwappedLoanToken > amountLoan) {
            unchecked {
                totalAmountReturned = amountSwappedLoanToken - amountLoan;
            }
        }

        // All calculation are in loanToken decimals
        uint256 userAmountDeposited = position.amountCollateralInLoanToken;
        uint8 loanTokenDecimals = s_loanTokenDecimals[position.loanToken];
        uint256 yieldFee = s_yieldFee.scaleTo(
            Math.STANDARD_DECIMALS,
            loanTokenDecimals
        );

        // Handle yield fee calculation and transfer
        uint256 amountFee;
        if (totalAmountReturned > userAmountDeposited) {
            uint256 yieldGenerated = totalAmountReturned - userAmountDeposited;
            amountFee = (yieldGenerated * yieldFee) / (10 ** loanTokenDecimals);
            _transferOut(position.loanToken, s_treasury, amountFee);
        }

        // Transfer remaining amount to user
        userAmountReturned = (totalAmountReturned - amountFee);
        _transferOut(position.loanToken, user, userAmountReturned);

        emit LeveragePositionClosed(user, positionId, userAmountReturned);
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
            FLError.FlashLeverage__EffectiveLtvTooHigh(desiredLtv, effectiveLtv)
        );
    }

    function _getAmountCollateralInLoanToken(
        address collateralToken,
        address loanToken,
        uint256 amountCollateral
    ) internal view returns (uint256) {
        return
            getCollateralValueInLoanToken(
                collateralToken,
                loanToken,
                amountCollateral
            ).scaleTo(
                    Math.STANDARD_DECIMALS,
                    IERC20Metadata(loanToken).decimals()
                );
    }

    function _transferBackRemaining(
        address token,
        uint256 actualSwapped,
        uint256 expectedAmount
    ) internal {
        if (actualSwapped > expectedAmount) {
            uint256 amountRemaining;
            unchecked {
                amountRemaining = actualSwapped - expectedAmount;
            }
            _transferOut(token, msg.sender, amountRemaining);
        }
    }

    /////////////////////////
    // Public and External View Functions

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
     * @notice Returns the current treasury address
     * @return treasury The address of the current treasury
     */
    function getTreasury() public view returns (address) {
        return s_treasury;
    }

    /**
     * @notice Returns the current yield fee configured in the protocol.
     * @return yieldFee The yield fee is a percentage value expressed in basis points
     */
    function getYieldFee() public view returns (uint256) {
        return s_yieldFee;
    }
}
