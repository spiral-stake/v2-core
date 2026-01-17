// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

/// @notice FlashLeverage
/// @notice Provide flash loan based leveraged yields on yield bearing tokens using morpho markets
/// @dev Integrates with custom SwapAggregator and MarketPositionManager modules.
/// @dev Creates individual position proxy contracts for each user to isolate their positions.

import {MarketPositionManager, MarketParams, Id, UserProxy, IERC20Metadata, FLError, Math, Position} from "./MarketPositionManager.sol";
import {SwapManager, SwapData} from "./SwapManager.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {LeverageParams} from "../structs/LeverageParams.sol";
import {LeveragePosition} from "../structs/LeveragePosition.sol";
import {CollateralTokenConfig} from "../structs/CollateralTokenConfig.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {IOracle} from "@morpho/interfaces/IOracle.sol";

contract FlashLeverage is
    MarketPositionManager,
    SwapManager,
    ReentrancyGuard,
    Ownable2Step
{
    using Math for uint256;

    /////////////////////////
    // Constants and Immutables

    /// @notice Safety buffer subtracted from liquidation LTV to determine max allowed LTV (18 decimals).
    /// @dev Protects positions from immediate liquidation due to price fluctuations after leveraging.
    uint256 public constant LIQUIDATION_BUFFER = 25e15; // 2.5%

    /// @notice Maximum yield fee percentage (18 decimals, where 1e18 = 100%)
    uint256 private constant MAX_YIELD_FEE = 10e16; // 10%

    /// @notice Maximum deposit fee for non-correlated assets (18 decimals, where 1e18 = 100%)
    uint256 private constant MAX_DEPOSIT_FEE = 1e16; // 1%

    /// @notice Implementation contract for creating individual user proxies
    address public immutable i_userProxyImplementation;

    /////////////////////////
    // Storage

    /// @notice Leverage positions of each user
    mapping(address user => LeveragePosition[]) private s_userLeveragePositions;

    /// @notice Treasury address to receive fees
    address public s_treasury;

    /// @notice Performance based yield fees on the effective yield generated
    uint256 public s_yieldFee;

    /// @notice Deposit fee for non-correlated assets
    uint256 public s_depositFee;

    /// @notice Tracks if a collateral-loan token pair is correlated
    mapping(address collateralToken => mapping(address loanToken => bool))
        public s_isCorrelated;

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

    event CollateralSupplied(
        address indexed user,
        uint256 indexed positionId,
        uint256 amountSuppliedInLoanToken
    );

    event LoanRepaid(
        address indexed user,
        uint256 indexed positionId,
        uint256 amountRepaid
    );

    event AdditionalBorrowed(
        address indexed user,
        uint256 indexed positionId,
        uint256 amountBorrowed
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

    /**
     * @notice Initializes the FlashLeverage contract.
     * @param morphoAddress Address of the Morpho protocol contract
     */
    constructor(
        address morphoAddress,
        address treasury
    ) Ownable(msg.sender) MarketPositionManager(morphoAddress) {
        if (morphoAddress == address(0) || treasury == address(0)) {
            revert FLError.FlashLeverage__CannotBeZeroAddress();
        }

        // Deploy the implementation contract to clone user proxies from
        i_userProxyImplementation = address(
            new UserProxy(address(this), morphoAddress)
        );

        s_treasury = treasury;
        s_yieldFee = MAX_YIELD_FEE;
        s_depositFee = MAX_DEPOSIT_FEE;
    }

    /////////////////////////
    // External Functions

    /**
     * @notice Creates leveraged positions by supplying collateralToken and borrowing via flashloan.
     * @param onBehalfOf The address of the user for whom the position is being created for.
     * @param params Struct containing leverage parameters including collateral, loan token, collateral amount, and other swap tokenConfigs.
     */
    function leverage(
        address onBehalfOf,
        LeverageParams calldata params
    )
        external
        validateOnBehalfOf(onBehalfOf)
        validateCollateralToken(params.collateralToken, params.loanToken)
        validateAmount(params.amountCollateral)
        validateAmount(params.amountFlashLoan)
    {
        _transferIn(
            params.collateralToken,
            msg.sender,
            params.amountCollateral
        );

        uint256 amountCollateral = _chargeDepositFeeIfNonCorrelated(
            params.collateralToken,
            params.collateralToken,
            params.loanToken,
            params.amountCollateral
        );

        uint256 positionId = s_userLeveragePositions[onBehalfOf].length;
        s_userLeveragePositions[onBehalfOf].push(
            LeveragePosition({
                open: true,
                collateralToken: params.collateralToken,
                loanToken: params.loanToken,
                amountCollateral: amountCollateral,
                userProxy: address(0), // Will be set in _handleLeverage
                amountDepositedInLoanToken: 0, // Will be set in _handleLeverage
                amountReturnedInLoanToken: 0
            })
        );

        bytes memory data = abi.encode(
            Action.LEVERAGE,
            onBehalfOf, // user
            positionId,
            amountCollateral,
            params.swapData,
            params.minTokenOut
        );

        i_morpho.flashLoan(params.loanToken, params.amountFlashLoan, data);
    }

    /**
     * @notice Closes an existing leveraged position and returns the final amount (in loan token) to the user.
     * @dev Only the leverage position's owner can call this function
     */
    function deleverage(
        uint256 positionId,
        SwapData memory swapData,
        uint256 minTokenOut
    ) external returns (uint256) {
        address user = msg.sender;

        LeveragePosition storage position = s_userLeveragePositions[user][
            positionId
        ];

        require(position.open, FLError.FlashLeverage__PositionAlreadyClosed());
        position.open = false;

        address collateralToken = position.collateralToken;
        address loanToken = position.loanToken;

        Position memory morphoPosition = getMorphoPosition(
            position.userProxy,
            collateralToken,
            loanToken
        );

        bytes memory data = abi.encode(
            Action.UNLEVERAGE,
            user, // user
            positionId,
            morphoPosition.borrowShares,
            morphoPosition.collateral, // amountLeveragedCollateral
            swapData,
            minTokenOut
        );

        uint256 amountFlashLoan;
        if (morphoPosition.borrowShares > 0) {
            amountFlashLoan = getSharesValueInLoanToken(
                collateralToken,
                loanToken,
                morphoPosition.borrowShares
            );

            i_morpho.flashLoan(loanToken, amountFlashLoan, data);
        } else {
            _handleDeleverage(amountFlashLoan, data);
        }

        return
            s_userLeveragePositions[user][positionId].amountReturnedInLoanToken;
    }

    /**
     * @notice Increases leverage on an existing position by borrowing more and adding to collateral.
     * @dev Only the position owner can call this function. Uses _handleLeverage internally.
     * @param positionId The unique identifier of the leverage position.
     * @param amountFlashLoan The amount to flash loan for increasing leverage.
     * @param swapData Swap configuration for converting loan token to collateral.
     * @param minTokenOut Minimum collateral tokens expected from swap.
     */
    function increaseLeverage(
        uint256 positionId,
        uint256 amountFlashLoan,
        SwapData calldata swapData,
        uint256 minTokenOut
    ) external validateAmount(amountFlashLoan) {
        address user = msg.sender;

        LeveragePosition storage position = s_userLeveragePositions[user][
            positionId
        ];

        require(position.open, FLError.FlashLeverage__PositionAlreadyClosed());

        bytes memory data = abi.encode(
            Action.LEVERAGE,
            user,
            positionId,
            uint256(0), // amountCollateral is 0, since we're only adding via flash loan
            swapData,
            minTokenOut
        );

        i_morpho.flashLoan(position.loanToken, amountFlashLoan, data);
    }

    /**
     * @notice Supplies additional collateral to an existing leverage position to reduce LTV.
     * @dev The collateral value is added to amountDepositedInLoanToken for accurate yield fee calculation.
     * @param user The address of the position owner.
     * @param positionId The unique identifier of the leverage position.
     * @param amountCollateral The amount of collateral tokens to supply.
     */
    function supplyCollateral(
        address user,
        uint256 positionId,
        uint256 amountCollateral
    ) external validateAmount(amountCollateral) {
        LeveragePosition storage position = s_userLeveragePositions[user][
            positionId
        ];

        require(position.open, FLError.FlashLeverage__PositionAlreadyClosed());

        address collateralToken = position.collateralToken;
        address loanToken = position.loanToken;

        _transferIn(collateralToken, msg.sender, amountCollateral);

        amountCollateral = _chargeDepositFeeIfNonCorrelated(
            collateralToken,
            collateralToken,
            loanToken,
            amountCollateral
        );

        _morphoSupplyCollateral(
            position.userProxy,
            s_marketParams[collateralToken][loanToken],
            amountCollateral
        );

        uint256 amountSuppliedInLoanToken = getCollateralValueInLoanToken(
            collateralToken,
            loanToken,
            amountCollateral
        );

        position.amountDepositedInLoanToken += amountSuppliedInLoanToken;

        emit CollateralSupplied(user, positionId, amountSuppliedInLoanToken);
    }

    /**
     * @notice Allows position owner to borrow additional loan tokens if within LTV limits.
     * @dev Only the position owner can call this function and works only for non-correlated pairs
     * @param positionId The unique identifier of the leverage position.
     * @param amountBorrow The amount of loan tokens to borrow.
     */
    function borrow(
        uint256 positionId,
        uint256 amountBorrow
    ) external validateAmount(amountBorrow) {
        address user = msg.sender;

        LeveragePosition storage position = s_userLeveragePositions[user][
            positionId
        ];

        require(position.open, FLError.FlashLeverage__PositionAlreadyClosed());
        require(
            !s_isCorrelated[position.collateralToken][position.loanToken],
            FLError.FlashLeverage__CannotBorrowForCorrelatedPair()
        );

        address collateralToken = position.collateralToken;
        address loanToken = position.loanToken;
        address userProxy = position.userProxy;

        _revertIfEffectiveLtvTooHigh(
            userProxy,
            collateralToken,
            loanToken,
            0,
            amountBorrow
        );

        _morphoBorrowViaProxy(
            userProxy,
            s_marketParams[collateralToken][loanToken],
            amountBorrow
        );

        _transferOut(loanToken, user, amountBorrow);

        position.amountDepositedInLoanToken -= amountBorrow;

        emit AdditionalBorrowed(user, positionId, amountBorrow);
    }

    /**
     * @notice Repays a portion of the borrowed debt on an existing leverage position to reduce LTV.
     * @dev The repaid amount is added to amountDepositedInLoanToken for accurate yield fee calculation.
     * @param user The address of the position owner.
     * @param positionId The unique identifier of the leverage position.
     * @param amountRepay The amount of loan tokens to repay.
     */
    function repay(
        address user,
        uint256 positionId,
        uint256 amountRepay,
        uint256 borrowShares // Can be 0, mostly used for full loan repayment
    ) external validateAmount(amountRepay) {
        LeveragePosition storage position = s_userLeveragePositions[user][
            positionId
        ];

        require(position.open, FLError.FlashLeverage__PositionAlreadyClosed());

        address collateralToken = position.collateralToken;
        address loanToken = position.loanToken;

        _transferIn(loanToken, msg.sender, amountRepay);

        amountRepay = _chargeDepositFeeIfNonCorrelated(
            loanToken,
            collateralToken,
            loanToken,
            amountRepay
        );

        _morphoRepay(
            position.userProxy,
            s_marketParams[collateralToken][loanToken],
            amountRepay,
            borrowShares
        );
        position.amountDepositedInLoanToken += amountRepay;

        emit LoanRepaid(user, positionId, amountRepay);
    }

    /**
     * @notice Allows owner to add support for new collateral tokens.
     * @param tokenConfig Collateral Token address and it's morpho market id
     */
    function addSupportedCollateralToken(
        CollateralTokenConfig calldata tokenConfig
    ) external onlyOwner {
        address collateralToken = tokenConfig.collateralToken;

        require(
            collateralToken != address(0),
            FLError.FlashLeverage__CannotBeZeroAddress()
        );

        // Morpho related
        MarketParams memory marketParams = i_morpho.idToMarketParams(
            Id.wrap(tokenConfig.morphoMarketId)
        );
        require(
            collateralToken == marketParams.collateralToken,
            FLError.FlashLeverage__InvalidCollateralToken()
        );
        _updateMarketParams(marketParams);

        s_isCorrelated[collateralToken][marketParams.loanToken] = tokenConfig
            .isCorrelated;
    }

    /**
     * @notice Adds a new valid swapRouter to execute the internal swaps
     * @param swapRouter The new swapRouter address
     * @dev Only callable by the contract owner. Validates that the new swap router is not zero address.
     */
    function addSwapRouter(address swapRouter) external onlyOwner {
        require(
            swapRouter != address(0),
            FLError.FlashLeverage__CannotBeZeroAddress()
        );

        _addSwapRouter(swapRouter);
    }

    /**
     * @notice Removes an existing swapRouter if it becomes compromised, or when we don't want to support it.
     * @param swapRouter Address of the swapRouter
     * @dev Only callable by the contract owner. Validates that the new swap router is not zero address.
     */
    function removeSwapRouter(address swapRouter) external onlyOwner {
        require(
            swapRouter != address(0),
            FLError.FlashLeverage__CannotBeZeroAddress()
        );

        _removeSwapRouter(swapRouter);
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
     * @param newYieldFee The new yield fee percentage (18 decimals, where 1e18 = 100%).
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
     * @notice Updates the deposit fee for non-correlated assets.
     * @param newDepositFee The new deposit fee percentage (18 decimals, where 1e18 = 100%).
     * @dev Can only be called by the contract owner.
     *      Reverts if the new fee exceeds `MAX_DEPOSIT_FEE`.
     */
    function updateDepositFee(uint256 newDepositFee) external onlyOwner {
        require(
            newDepositFee <= MAX_DEPOSIT_FEE,
            FLError.FlashLeverage__InvalidDepositFee()
        );

        s_depositFee = newDepositFee;
    }

    /**
     * @notice Enables recovery mode on a user's proxy contract to allow emergency withdrawals.
     * @dev Only callable by the contract owner in case of emergencies or stuck funds.
     * @param userProxy The address of the user proxy contract to enable recovery mode on.
     */
    function enableRecoveryMode(address userProxy) external onlyOwner {
        UserProxy(userProxy).enableRecoveryMode();
    }

    /**
     * @notice Overrides renounceOwnership to prevent ownership renunciation.
     * @dev Intentionally disabled to retain upgradeability and collateral support management.
     */
    function renounceOwnership() public pure override(Ownable) {
        revert FLError.FlashLeverage__OwnershipRenunciationDisabled();
    }

    /////////////////////////
    // Internal and Private Functions

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
            uint256 positionId,
            uint256 amountCollateral,
            SwapData memory swapData,
            uint256 minTokenOut
        ) = abi.decode(
                data,
                (Action, address, uint256, uint256, SwapData, uint256)
            );

        LeveragePosition storage position = s_userLeveragePositions[user][
            positionId
        ];

        address collateralToken = position.collateralToken;
        address loanToken = position.loanToken;
        address userProxy = position.userProxy;

        // Swap amount loan -> collateral token
        uint256 amountSwappedCollateral = _swapToken(
            loanToken,
            collateralToken,
            amountLoan,
            swapData,
            minTokenOut
        );

        // Position's final collateral after leveraging
        uint256 amountLeveragedCollateral = amountCollateral +
            amountSwappedCollateral;

        _revertIfEffectiveLtvTooHigh(
            userProxy,
            collateralToken,
            loanToken,
            amountLeveragedCollateral,
            amountLoan
        );

        // Create new proxy only if this is a new position
        if (userProxy == address(0)) {
            userProxy = _createUserProxy(user);
            position.userProxy = userProxy;
        }

        _supplyCollateralAndBorrowViaProxy(
            userProxy,
            collateralToken,
            loanToken,
            amountLeveragedCollateral,
            amountLoan
        );

        // Repay the flash loan, with borrowed loan token
        _forceApprove(loanToken, address(i_morpho), amountLoan);

        if (amountCollateral > 0) {
            // Position Tracking Related: Amount Collateral Deposited in loan token
            uint256 amountDepositedInLoanToken = getCollateralValueInLoanToken(
                collateralToken,
                loanToken,
                amountCollateral
            );

            position.amountDepositedInLoanToken += amountDepositedInLoanToken;

            emit LeveragePositionOpened(
                user,
                positionId,
                amountDepositedInLoanToken
            );
        }
    }

    /**
     * @notice Handles internal logic after flashloan is received for deleveraging.
     * @dev Repays existing borrow, withdraws collateral, swaps it to the loan token,
     *      repays the flashloan, and returns excess (initial collateral + leveraged yield)
     * @param amountLoan Amount borrowed via flashloan for debt repayment. Can be 0, if the loan is fully repaid
     * @param data Encoded deleverage action data.
     */
    function _handleDeleverage(
        uint256 amountLoan,
        bytes memory data
    ) internal override nonReentrant {
        (
            ,
            address user,
            uint256 positionId,
            uint256 borrowShares,
            uint256 amountLeveragedCollateral,
            SwapData memory swapData,
            uint256 minTokenOut
        ) = abi.decode(
                data,
                (Action, address, uint256, uint256, uint256, SwapData, uint256)
            );

        LeveragePosition storage position = s_userLeveragePositions[user][
            positionId
        ];

        // Close the position's existing loan, with the flashloan, to withdraw position's required collateral
        _repayAndWithdrawCollateralViaProxy(
            position.userProxy,
            position.collateralToken,
            position.loanToken,
            amountLoan,
            amountLeveragedCollateral,
            borrowShares
        );

        // Swap withdrawn collateral -> loan token
        uint256 amountSwappedLoanToken = _swapToken(
            position.collateralToken,
            position.loanToken,
            amountLeveragedCollateral,
            swapData,
            minTokenOut
        );

        if (amountLoan > 0) {
            // Repay the flash loan, with swapped loan token
            _forceApprove(position.loanToken, address(i_morpho), amountLoan);
        }

        uint256 totalAmountReturned;
        if (amountSwappedLoanToken > amountLoan) {
            unchecked {
                totalAmountReturned = amountSwappedLoanToken - amountLoan;
            }
        }

        uint256 amountFee; // Only charge yield fee for correlated assets
        if (s_isCorrelated[position.collateralToken][position.loanToken]) {
            // All calculation are in loanToken decimals
            uint256 amountDeposited = position.amountDepositedInLoanToken;

            if (totalAmountReturned > amountDeposited) {
                uint256 yieldGenerated = totalAmountReturned - amountDeposited;
                amountFee = yieldGenerated.mulDown(s_yieldFee);
                _transferOut(position.loanToken, s_treasury, amountFee);
            }
        }

        // Transfer remaining amount to user
        uint256 amountReturned = (totalAmountReturned - amountFee);
        _transferOut(position.loanToken, user, amountReturned);

        position.amountReturnedInLoanToken = amountReturned;
        emit LeveragePositionClosed(user, positionId, amountReturned);
    }

    /**
     * @notice Charges deposit fee for non-correlated assets.
     * @param token Address of the token to charge fee on.
     * @param collateralToken Address of the collateral token (for correlation check).
     * @param loanToken Address of the loan token (for correlation check).
     * @param amount The amount on which to charge fee.
     * @return amountAfterFee The amount after deducting the fee.
     */
    function _chargeDepositFeeIfNonCorrelated(
        address token,
        address collateralToken,
        address loanToken,
        uint256 amount
    ) internal returns (uint256 amountAfterFee) {
        if (s_isCorrelated[collateralToken][loanToken]) {
            return amount;
        }

        uint256 feeAmount = amount.mulDown(s_depositFee);

        if (feeAmount > 0) {
            _transferOut(token, s_treasury, feeAmount);
        }

        amountAfterFee = amount - feeAmount;
    }

    /**
     * @dev Validates that the final LTV after leverage operation doesn't exceed the max LTV.
     * @param userProxy Address of the user's proxy contract (address(0) for new positions).
     * @param collateralToken Address of the collateral token.
     * @param loanToken Address of the loan token.
     * @param amountLeveragedCollateral Total amount of collateral after leverage.
     * @param amountLoan Amount Loan in loan token decimals
     */
    function _revertIfEffectiveLtvTooHigh(
        address userProxy,
        address collateralToken,
        address loanToken,
        uint256 amountLeveragedCollateral,
        uint256 amountLoan
    ) internal view {
        // Add existing position values if proxy exists
        if (userProxy != address(0)) {
            Position memory morphoPosition = getMorphoPosition(
                userProxy,
                collateralToken,
                loanToken
            );
            amountLeveragedCollateral += morphoPosition.collateral;
            amountLoan += getSharesValueInLoanToken(
                collateralToken,
                loanToken,
                morphoPosition.borrowShares
            );
        }

        // Standardising decimals for calculations
        uint8 loanTokenDecimals = s_loanTokenDecimals[loanToken];

        amountLoan = amountLoan.scaleTo(
            loanTokenDecimals,
            Math.STANDARD_DECIMALS
        );

        uint256 amountCollateralInLoanToken = getCollateralValueInLoanToken(
            collateralToken,
            loanToken,
            amountLeveragedCollateral
        ).scaleTo(loanTokenDecimals, Math.STANDARD_DECIMALS);

        uint256 effectiveLtv = amountLoan.divDown(amountCollateralInLoanToken);
        uint256 maxLtv = getMaxLtv(collateralToken, loanToken);

        require(
            effectiveLtv <= maxLtv,
            FLError.FlashLeverage__ExceedsMaxLTV(effectiveLtv, maxLtv)
        );
    }

    /**
     * @notice Creates a new proxy contract for isolating a user's leverage position.
     * @dev Clones the implementation contract and initializes it for the user.
     * @param user The address of the user to create a proxy for.
     * @return proxy The address of the newly created user proxy contract.
     */
    function _createUserProxy(address user) private returns (address proxy) {
        proxy = Clones.clone(i_userProxyImplementation);
        UserProxy(proxy).initialize(user);
    }

    /////////////////////////
    // Public and External View Functions

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
     * @return Equivalent amount in loan token (using the token's native decimals).
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
                s_loanTokenDecimals[loanToken]
            );
    }
}
