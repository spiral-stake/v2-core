// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import {IPositionManager} from "../../interfaces/IPositionManager.sol";
import {IStblUSD} from "../../interfaces/IStblUSD.sol";
import {IERC3156FlashBorrower} from "@openzeppelin/contracts/interfaces/IERC3156FlashBorrower.sol";
import {IERC3156FlashLender} from "@openzeppelin/contracts/interfaces/IERC3156FlashLender.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {TokenHelper} from "../libraries/TokenHelper.sol";
import {Errors} from "../libraries/Errors.sol";
import {Math} from "../libraries/Math.sol";
import {Position} from "../structs/Position.sol";

import {console} from "forge-std/console.sol";

/**
 * @title PositionManager
 * @notice Manages user positions that mint StblUSD against supported collateral tokens.
 * @dev Implements core CDP logic including collateral deposits, StblUSD minting, LTV checks, and liquidations.
 */
contract PositionManager is Ownable2Step, TokenHelper, IPositionManager {
    using Math for uint256;

    /////////////////////////
    // Constants and Immutables

    /// @notice Reference to the StblUSD stablecoin contract
    IStblUSD private immutable StblUSD;

    /// @notice Additional precision multiplier for price feeds
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;

    /// @notice Liquidation threshold LTV (91.5% in 1e18 precision)
    uint256 public constant LIQ_LTV = 915e15;

    /// @notice Maximum allowed LTV for minting StblUSD (90% in 1e18 precision)
    uint256 public constant MAX_LTV = 900e15;

    uint256 public constant MAX_LOAN = 90 days;

    // ERC3156 Flash Loan constants
    bytes32 public constant FLASHLOAN_SUCCESS_CALLBACK =
        keccak256("ERC3156FlashBorrower.onFlashLoan");

    /////////////////////////
    // Storage

    /// @notice Mapping of supported collateral tokens and their associated Chainlink price feeds
    mapping(address collateralToken => address priceFeed) private s_priceFeeds;

    uint256 private s_totalPositions;

    mapping(uint256 positionId => Position) private s_positions;

    mapping(address user => uint256[] positionIds) private s_userPositionIds;

    /// @notice Address that receives protocol revenue or seized collateral during liquidation
    address private s_treasury;

    /////////////////////////
    // Modifiers

    modifier isGreaterThanZero(uint256 value) {
        require(value > 0, Errors.PositionManager__ValueCannotBeZero());
        _;
    }

    modifier isSupportedCollateralToken(address token) {
        require(
            s_priceFeeds[token] != address(0),
            Errors.PositionManager__UnsupportedCollateralToken()
        );
        _;
    }

    /////////////////////////
    // Constructor

    /**
     * @param _StblUSD Address of the StblUSD token
     * @param treasury Address of the treasury
     */
    constructor(address _StblUSD, address treasury) Ownable(msg.sender) {
        StblUSD = IStblUSD(_StblUSD);
        s_treasury = treasury;
    }

    /////////////////////////
    // External Functions

    /**
     * @notice Opens a new position with specified collateral and mints StblUSD.
     * @param collateralToken Address of the collateral token to deposit.
     * @param amountCollateral Amount of collateral to deposit.
     * @param amountToMint Amount of StblUSD to mint.
     * @return positionId id of the position created
     */
    function openPosition(
        address collateralToken,
        uint256 amountCollateral,
        uint256 amountToMint
    )
        external
        isSupportedCollateralToken(collateralToken)
        returns (uint256 positionId)
    {
        address _msgSender = msg.sender;
        positionId = s_totalPositions;

        Position memory newPosition = Position({
            owner: _msgSender,
            collateralToken: collateralToken,
            collateralDeposited: 0,
            StblUSDMinted: 0
        });

        s_positions[positionId] = newPosition;

        depositCollateralAndMintStblUSD(
            positionId,
            amountCollateral,
            amountToMint
        );

        s_userPositionIds[_msgSender].push(positionId);
        s_totalPositions++;
    }

    /**
     * @notice Deposits collateral and mints StblUSD in a single transaction.
     * @param positionId ID of the position to modify.
     * @param amountCollateral Amount of collateral to deposit.
     * @param amountToMint Amount of StblUSD to mint.
     */
    function depositCollateralAndMintStblUSD(
        uint256 positionId,
        uint256 amountCollateral,
        uint256 amountToMint
    ) public {
        depositCollateral(positionId, amountCollateral);
        mintStblUSD(positionId, amountToMint);
    }

    /**
     * @notice Deposits supported collateral into a position.
     * @dev Transfers tokens and updates position state.
     * @param positionId ID of the position to deposit collateral into.
     * @param amountCollateral Amount of collateral to deposit.
     */
    function depositCollateral(
        uint256 positionId,
        uint256 amountCollateral
    ) public isGreaterThanZero(amountCollateral) {
        Position storage position = s_positions[positionId];

        _transferIn(position.collateralToken, msg.sender, amountCollateral);

        position.collateralDeposited += amountCollateral;
    }

    /**
     * @notice Mints StblUSD against a position's deposited collateral.
     * @dev Reverts if resulting LTV exceeds MAX_LTV.
     * @param positionId ID of the position to mint StblUSD from.
     * @param amountToMint Amount of StblUSD to mint.
     */
    function mintStblUSD(
        uint256 positionId,
        uint256 amountToMint
    ) public isGreaterThanZero(amountToMint) {
        Position storage position = s_positions[positionId];
        require(msg.sender == position.owner);

        position.StblUSDMinted += amountToMint;

        _revertIfExceedsMaxLTV(positionId);
        StblUSD.mint(position.owner, amountToMint);
    }

    /**
     * @notice Burns StblUSD and redeems corresponding collateral in one transaction.
     * @param positionId ID of the position to update.
     * @param amountCollateral Amount of collateral to redeem.
     * @param amountToBurn Amount of StblUSD to burn.
     */
    function redeemCollateralAndBurnStblUSD(
        uint256 positionId,
        uint256 amountCollateral,
        uint256 amountToBurn
    ) external {
        burnStblUSD(positionId, amountToBurn);
        redeemCollateral(positionId, amountCollateral);
    }

    /**
     * @notice Redeems collateral from a position.
     * @param positionId ID of the position to redeem from.
     * @param amountCollateral Amount of collateral to redeem.
     */
    function redeemCollateral(
        uint256 positionId,
        uint256 amountCollateral
    ) public isGreaterThanZero(amountCollateral) {
        require(msg.sender == s_positions[positionId].owner);
        _redeemCollateral(msg.sender, positionId, amountCollateral);
    }

    /**
     * @notice Burns StblUSD from sender and updates the position state.
     * @param positionId ID of the position to update.
     * @param amountToBurn Amount of StblUSD to burn.
     */
    function burnStblUSD(
        uint256 positionId,
        uint256 amountToBurn
    ) public isGreaterThanZero(amountToBurn) {
        _burnStblUSD(msg.sender, positionId, amountToBurn);
    }

    /**
     * @notice Liquidates an under-collateralized position and claims the collateral.
     * @param positionId ID of the position to liquidate.
     */
    function liquidate(uint256 positionId) external {
        address _msgSender = msg.sender;
        uint256 positionLTV = _calcLTV(positionId);

        require(
            positionLTV >= LIQ_LTV,
            Errors.PositionManager__IsUnderLiqLTV()
        );

        Position storage position = s_positions[positionId];
        uint256 debtToCover = position.StblUSDMinted;
        uint256 amountCollateralSeized = position.collateralDeposited;

        _redeemCollateral(_msgSender, positionId, amountCollateralSeized);
        _burnStblUSD(_msgSender, positionId, debtToCover);
    }

    /// @notice Initiates a flash loan in StblUSD to the specified receiver.
    /// @dev Assumes zero fee for the flash loan. Expects repayment plus amount before function completes.
    /// @param receiver The contract implementing `onFlashLoan`, which will receive the funds.
    /// @param loanToken Must be StblUSD; flash loans are only supported for this token.
    /// @param amountLoan The amount of StblUSD to loan.
    /// @param data Arbitrary data to pass to the receiver's `onFlashLoan` callback.
    /// @return success Boolean indicating success of flash loan execution.
    function flashLoan(
        IERC3156FlashBorrower receiver,
        address loanToken,
        uint256 amountLoan,
        bytes calldata data
    ) external override isGreaterThanZero(amountLoan) returns (bool success) {
        require(
            loanToken == address(StblUSD),
            Errors.PositionManager__InvalidFlashLoanToken()
        );
        require(
            address(receiver) != address(0),
            Errors.PositionManager__InvalidReceiverAddress()
        );

        uint256 initialBalance = StblUSD.balanceOf(address(this));
        StblUSD.mint(address(receiver), amountLoan);

        require(
            receiver.onFlashLoan(
                msg.sender,
                address(StblUSD),
                amountLoan,
                0, // Zero fees temporarily
                data
            ) == FLASHLOAN_SUCCESS_CALLBACK,
            Errors.PositionManager__FlashMintCallbackFailed()
        );

        uint256 finalBalance = StblUSD.balanceOf(address(this));

        require(
            finalBalance >= initialBalance + amountLoan,
            Errors.PositionManager__FlashMintNotRepaid()
        );

        StblUSD.burn(address(this), amountLoan);
        return true;
    }

    /**
     * @notice Adds or removes support for collateral tokens.
     * @param collateralTokens List of collateral token addresses.
     * @param priceFeedAddress Corresponding Chainlink price feed addresses. Use address(0) to remove support.
     */
    function addSupportedCollateralTokens(
        address[] memory collateralTokens,
        address[] memory priceFeedAddress
    ) external onlyOwner {
        require(
            collateralTokens.length == priceFeedAddress.length,
            "Length Mismatch"
        );

        for (uint256 i = 0; i < collateralTokens.length; i++) {
            require(
                collateralTokens[i] != address(0),
                Errors.PositionManager__InvalidTokenAddress()
            );

            if (priceFeedAddress[i] != address(0)) {
                require(
                    AggregatorV3Interface(priceFeedAddress[i]).decimals() > 0,
                    Errors.PositionManager__InvalidPriceFeedAddress()
                );
            }

            s_priceFeeds[collateralTokens[i]] = priceFeedAddress[i];
        }
    }

    /**
     * @notice Updates the treasury address.
     * @param newTreasuryAddress New treasury address.
     */
    function updateTreasury(address newTreasuryAddress) external onlyOwner {
        s_treasury = newTreasuryAddress;
    }

    /**
     * @notice Overrides renounceOwnership to prevent ownership renunciation.
     * @dev Intentionally disabled to retain upgradeability and collateral support management.
     */
    function renounceOwnership() public override {}

    /////////////////////////
    // Internal Functions

    function _redeemCollateral(
        address to,
        uint256 positionId,
        uint256 amountCollateral
    ) private {
        Position storage position = s_positions[positionId];
        position.collateralDeposited -= amountCollateral;

        _revertIfExceedsMaxLTV(positionId);
        _transferOut(position.collateralToken, to, amountCollateral);
    }

    function _burnStblUSD(
        address burnFrom,
        uint256 positionId,
        uint256 amountToBurn
    ) private {
        Position storage position = s_positions[positionId];
        position.StblUSDMinted -= amountToBurn;

        StblUSD.burn(burnFrom, amountToBurn);
    }

    function _revertIfExceedsMaxLTV(uint256 positionId) internal view {
        require(
            _calcLTV(positionId) <= MAX_LTV,
            Errors.PositionManager__MintExceedsMaxLTV()
        );
    }

    function _calcLTV(uint256 positionId) internal view returns (uint256) {
        uint256 totalStblUSDMinted = s_positions[positionId].StblUSDMinted;
        uint256 totalCollateralValueInUsd = getPositionCollateralValue(
            positionId
        );

        if (totalStblUSDMinted == 0) return 0;

        return totalStblUSDMinted.divDown(totalCollateralValueInUsd);
    }

    /////////////////////////
    // External View Functions

    /// @notice Returns the address of the StblUSD token
    function getStblUSD() external view override returns (address) {
        return address(StblUSD);
    }

    /// @notice Returns an array of position IDs associated with a given user.
    /// @param user The address of the user whose position IDs are being queried.
    /// @return An array of position IDs owned or created by the user.
    function getUserPositionIds(
        address user
    ) external view returns (uint256[] memory) {
        return s_userPositionIds[user];
    }

    /**
     * @notice Returns the current Position struct for a given position ID.
     * @param positionId ID of the position to fetch.
     * @return Position data including owner, token, collateral, and debt.
     */
    function getPosition(
        uint256 positionId
    ) external view returns (Position memory) {
        return s_positions[positionId];
    }

    /**
     * @notice Returns the current Loan-to-Value (LTV) ratio of a position.
     * @param positionId ID of the position to evaluate.
     * @return Current LTV ratio (scaled by 1e18).
     */
    function getPositionLTV(uint256 positionId) public view returns (uint256) {
        return _calcLTV(positionId);
    }

    /**
     * @notice Returns the total collateral value (in USD) for a position.
     * @param positionId ID of the position to evaluate.
     * @return totalCollateralValueInUsd Total collateral value in 1e18 USD units.
     */
    function getPositionCollateralValue(
        uint256 positionId
    ) public view returns (uint256 totalCollateralValueInUsd) {
        Position memory position = s_positions[positionId];
        return
            getTokenUsdValue(
                position.collateralToken,
                position.collateralDeposited
            );
    }

    /**
     * @notice Converts a token amount into its USD equivalent using Chainlink.
     * @param token Address of the token.
     * @param amount Token amount to convert.
     * @return USD value of the token amount (scaled to 1e18).
     */
    function getTokenUsdValue(
        address token,
        uint256 amount
    ) public view returns (uint256) {
        if (amount == 0) return 0;

        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            s_priceFeeds[token]
        );
        (, int256 price, , , ) = priceFeed.latestRoundData();

        return
            ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / Math.ONE;
    }

    function flashFee(
        address token,
        uint256 amount
    ) external view override returns (uint256) {
        return 0; // Flash fee is 0 for now
    }

    function maxFlashLoan(
        address token
    ) external view override returns (uint256) {
        return type(uint256).max;
    }
}
