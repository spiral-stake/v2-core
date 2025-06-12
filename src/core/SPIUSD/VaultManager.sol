// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import {IVaultManager} from "../../interfaces/IVaultManager.sol";
import {ISPIUSD} from "../../interfaces/ISPIUSD.sol";
import {Vault} from "../structs/Vault.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {TokenHelper} from "../libraries/TokenHelper.sol";
import {Errors} from "../libraries/Errors.sol";
import {Math} from "../libraries/Math.sol";

/**
 * @title VaultManager
 * @notice Manages user vaults that mint SPIUSD against supported collateral tokens.
 * @dev Implements core CDP logic including collateral deposits, SPIUSD minting, LTV checks, and liquidations.
 */
contract VaultManager is IVaultManager, Ownable2Step, TokenHelper {
    using Math for uint256;

    /////////////////////////
    // Constants and Immutables

    /// @notice Reference to the SPIUSD stablecoin contract
    ISPIUSD private immutable SPIUSD;

    /// @notice Additional precision multiplier for price feeds
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;

    /// @notice Liquidation threshold LTV (91.5% in 1e18 precision)
    uint256 private constant LIQ_LTV = 915e15;

    /// @notice Maximum allowed LTV for minting SPIUSD (90% in 1e18 precision)
    uint256 private constant MAX_LTV = 900e15;

    /////////////////////////
    // Storage

    /// @notice Mapping of supported collateral tokens and their associated Chainlink price feeds
    mapping(address collateralToken => address priceFeed) private s_priceFeeds;

    /// @notice Mapping of user vaults per collateral token
    mapping(address user => mapping(address collateralToken => Vault))
        private s_userVaults;

    /// @notice Address that receives protocol revenue or seized collateral during liquidation
    address private s_treasury;

    /////////////////////////
    // Events

    /// @notice Emitted when collateral is deposited into a user vault
    event CollateralDeposited(
        address indexed user,
        address indexed collateralToken,
        uint256 indexed amountCollateral
    );

    /////////////////////////
    // Modifiers

    modifier isGreaterThanZero(uint256 value) {
        require(value > 0, Errors.VaultManager__ValueCannotBeZero());
        _;
    }

    modifier isSupportedCollateralToken(address token) {
        require(
            s_priceFeeds[token] != address(0),
            Errors.VaultManager__UnsupportedCollateralToken()
        );
        _;
    }

    /////////////////////////
    // Constructor

    /**
     * @param _SPIUSD Address of the SPIUSD token
     * @param treasury Address of the treasury
     */
    constructor(address _SPIUSD, address treasury) Ownable(msg.sender) {
        SPIUSD = ISPIUSD(_SPIUSD);
        s_treasury = treasury;
    }

    /////////////////////////
    // External Functions

    /**
     * @notice Deposits collateral and mints SPIUSD in a single transaction
     * @param collateralToken Address of the collateral token
     * @param amountCollateral Amount of collateral to deposit
     * @param amountToMint Amount of SPIUSD to mint
     */
    function depositCollateralAndMintSPIUSD(
        address collateralToken,
        uint256 amountCollateral,
        uint256 amountToMint
    ) external override {
        depositCollateral(collateralToken, amountCollateral);
        mintSPIUSD(collateralToken, amountToMint);
    }

    /**
     * @notice Deposits supported collateral into user's vault
     * @dev Transfers tokens and updates vault state
     * @param collateralToken Address of the collateral token
     * @param amountCollateral Amount of collateral to deposit
     */
    function depositCollateral(
        address collateralToken,
        uint256 amountCollateral
    )
        public
        override
        isSupportedCollateralToken(collateralToken)
        isGreaterThanZero(amountCollateral)
    {
        address _msgSender = msg.sender;
        _transferIn(collateralToken, _msgSender, amountCollateral);

        Vault storage vault = s_userVaults[_msgSender][collateralToken];
        vault.collateralDeposited += amountCollateral;

        emit CollateralDeposited(_msgSender, collateralToken, amountCollateral);
    }

    /**
     * @notice Mints SPIUSD against user's deposited collateral
     * @dev Reverts if resulting LTV exceeds MAX_LTV
     * @param collateralToken Address of the collateral token
     * @param amountToMint Amount of SPIUSD to mint
     */
    function mintSPIUSD(
        address collateralToken,
        uint256 amountToMint
    ) public override isGreaterThanZero(amountToMint) {
        address _msgSender = msg.sender;
        Vault storage vault = s_userVaults[_msgSender][collateralToken];
        vault.SPIUSDMinted += amountToMint;

        _revertIfExceedsMaxLTV(_msgSender, collateralToken);
        SPIUSD.mint(_msgSender, amountToMint);
    }

    /**
     * @notice Burns SPIUSD and redeems corresponding collateral in one transaction
     * @param collateralToken Address of the collateral token
     * @param amountCollateral Amount of collateral to redeem
     * @param amountToBurn Amount of SPIUSD to burn
     */
    function redeemCollateralAndBurnSPIUSD(
        address collateralToken,
        uint256 amountCollateral,
        uint256 amountToBurn
    ) external override {
        burnSPIUSD(collateralToken, amountToBurn);
        redeemCollateral(collateralToken, amountCollateral);
    }

    /**
     * @notice Redeems collateral from user's vault
     * @param collateralToken Address of the collateral token
     * @param amountCollateral Amount of collateral to redeem
     */
    function redeemCollateral(
        address collateralToken,
        uint256 amountCollateral
    ) public override isGreaterThanZero(amountCollateral) {
        _redeemCollateral(
            msg.sender,
            msg.sender,
            collateralToken,
            amountCollateral
        );
    }

    /**
     * @notice Burns SPIUSD from user and updates vault state
     * @param collateralToken Address of the collateral token
     * @param amountToBurn Amount of SPIUSD to burn
     */
    function burnSPIUSD(
        address collateralToken,
        uint256 amountToBurn
    ) public override isGreaterThanZero(amountToBurn) {
        _burnSPIUSD(msg.sender, msg.sender, collateralToken, amountToBurn);
    }

    /**
     * @notice Allows third party to liquidate an unsafe vault and claim collateral
     * @param user Vault owner to be liquidated
     * @param collateralToken Address of the collateral token
     */
    function liquidate(
        address user,
        address collateralToken
    ) external override {
        address _msgSender = msg.sender;
        uint256 userVaultLTV = _calcLTV(user, collateralToken);

        require(userVaultLTV >= LIQ_LTV, Errors.VaultManager__IsUnderLiqLTV());

        Vault storage vault = s_userVaults[user][collateralToken];
        uint256 debtToCover = vault.SPIUSDMinted;
        uint256 amountCollateralSeized = vault.collateralDeposited;

        _redeemCollateral(
            user,
            _msgSender,
            collateralToken,
            amountCollateralSeized
        );
        _burnSPIUSD(_msgSender, user, collateralToken, debtToCover);
    }

    /**
     * @notice Adds or removes support for a collateral token.
     * @param collateralToken Collateral token address.
     * @param priceFeedAddress Price feed address. Use address(0) to remove support.
     */
    function setCollateralTokenSupport(
        address[] memory collateralToken,
        address[] memory priceFeedAddress
    ) external onlyOwner {
        require(
            collateralToken.length == priceFeedAddress.length,
            "Length Mismatch"
        );

        for (uint256 i = 0; i < collateralToken.length; i++) {
            require(
                collateralToken[i] != address(0),
                Errors.VaultManager__InvalidTokenAddress()
            );

            if (priceFeedAddress[i] != address(0)) {
                require(
                    AggregatorV3Interface(priceFeedAddress[i]).decimals() > 0,
                    Errors.VaultManager__InvalidPriceFeedAddress()
                );
            }

            s_priceFeeds[collateralToken[i]] = priceFeedAddress[i];
        }
    }

    /**
     * @notice Updates the treasury address
     * @param newTreasuryAddress New treasury address
     */
    function updateTreasury(address newTreasuryAddress) external onlyOwner {
        s_treasury = newTreasuryAddress;
    }

    /**
     * @notice Overrides renounceOwnership to prevent ownership renunciation
     * @dev This function is intentionally empty to block the ability to renounce ownership
     * since this contract requires ongoing management for adding supported collateral
     * token integrations and updating parameters.
     */
    function renounceOwnership() public override {}

    /////////////////////////
    // Internal Functions

    function _redeemCollateral(
        address from,
        address to,
        address collateralToken,
        uint256 amountCollateral
    ) private {
        Vault storage vault = s_userVaults[from][collateralToken];
        vault.collateralDeposited -= amountCollateral;

        _revertIfExceedsMaxLTV(from, collateralToken);
        _transferOut(collateralToken, to, amountCollateral);
    }

    function _burnSPIUSD(
        address burnFrom,
        address onBehalfOf,
        address collateralToken,
        uint256 amountToBurn
    ) private {
        Vault storage vault = s_userVaults[onBehalfOf][collateralToken];
        vault.SPIUSDMinted -= amountToBurn;

        SPIUSD.burn(burnFrom, amountToBurn);
    }

    function _revertIfExceedsMaxLTV(
        address user,
        address collateralToken
    ) internal view {
        require(
            _calcLTV(user, collateralToken) <= MAX_LTV,
            Errors.VaultManager__MintExceedsMaxLTV()
        );
    }

    function _calcLTV(
        address user,
        address collateralToken
    ) internal view returns (uint256) {
        uint256 totalSPIUSDMinted = s_userVaults[user][collateralToken]
            .SPIUSDMinted;
        uint256 totalCollateralValueInUsd = getUserVaultCollateralValue(
            user,
            collateralToken
        );

        // LTV (Loan To Value Ratio) = SPIUSDMinted / collateralValue
        return totalSPIUSDMinted.divDown(totalCollateralValueInUsd);
    }

    /////////////////////////
    // External View Functions

    /**
     * @notice Returns the current Loan-to-Value ratio of a user's vault
     */
    function getUserVaultLTV(
        address user,
        address collateralToken
    ) public view returns (uint256) {
        return _calcLTV(user, collateralToken);
    }

    /**
     * @notice Returns total collateral value (in USD) for a user vault
     */
    function getUserVaultCollateralValue(
        address user,
        address collateralToken
    ) public view returns (uint256 totalCollateralValueInUsd) {
        uint256 amountCollateral = s_userVaults[user][collateralToken]
            .collateralDeposited;
        return getTokenUsdValue(collateralToken, amountCollateral);
    }

    /**
     * @notice Converts token amount to USD value using Chainlink price feed
     */
    function getTokenUsdValue(
        address token,
        uint256 amount
    ) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            s_priceFeeds[token]
        );
        (, int256 price, , , ) = priceFeed.latestRoundData();

        return
            ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / Math.ONE;
    }
}
