// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import {IVaultManager} from "../../interfaces/IVaultManager.sol";
import {TokenHelper} from "../libraries/TokenHelper.sol";
import {ISPIUSD} from "../../interfaces/ISPIUSD.sol";
import {Errors} from "../libraries/Errors.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Vault} from "../structs/Vault.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {Math} from "../libraries/Math.sol";

/**
 * @title Vault Manager
 *
 *
 *
 */
contract VaultManager is IVaultManager, Ownable2Step, TokenHelper {
    using Math for uint256;

    /////////////////////////
    // Constants and Immutables

    ISPIUSD private immutable SPIUSD;

    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant LIQ_LTV = 915e15; // 91.5% in 1e18 precision
    uint256 private constant MAX_LTV = 900e15; // 90% in 1e18 precision
    uint256 private constant LIQUIDATION_BONUS = 50e15; // 5% in 1e18 precision

    /////////////////////////
    // Storage

    mapping(address collateralToken => address priceFeed) private s_priceFeeds;

    address[] private s_collateralTokens;

    mapping(address user => mapping(address collateralToken => Vault))
        private s_userVault;

    address private s_treasury;

    /////////////////////////
    // Events
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
    // Functions

    constructor(address SPIUSD, address treasury) Ownable(msg.sender) {
        SPIUSD = ISPIUSD(SPIUSD);
        s_treasury = treasury;
    }

    /////////////////////////
    // External Functions

    function depositCollateralAndMintSPIUSD(
        address collateralToken,
        uint256 amountCollateral,
        uint256 amountToMint
    ) external override {
        depositCollateral(collateralToken, amountCollateral);
        mintSPIUSD(collateralToken, amountToMint);
    }

    /**
     *
     * steps
     * 1. check if collateral token is supported
     * 2. transferIn the collateral
     * 3. update users collateral balance
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

        Vault storage vault = s_userVault[_msgSender][collateralToken];
        vault.collateralDeposited += amountCollateral;

        emit CollateralDeposited(_msgSender, collateralToken, amountCollateral);
    }

    function mintSPIUSD(
        address collateralToken,
        uint256 amountToMint
    ) public override isGreaterThanZero(amountToMint) {
        address _msgSender = msg.sender;

        Vault storage vault = s_userVault[_msgSender][collateralToken];
        vault.SPIUSDMinted += amountToMint;

        _revertIfExceedsMaxLTV(_msgSender, collateralToken);

        SPIUSD.mint(_msgSender, amountToMint);
    }

    function redeemCollateralAndBurnSPIUSD(
        address collateralToken,
        uint256 amountCollateral,
        uint256 amountToBurn
    ) external override {
        burnSPIUSD(collateralToken, amountToBurn);
        redeemCollateral(collateralToken, amountCollateral); // checks if exceeds max LTV
    }

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

    function burnSPIUSD(
        address collateralToken,
        uint256 amountToBurn
    ) public override isGreaterThanZero(amountToBurn) {
        _burnSPIUSD(msg.sender, msg.sender, collateralToken, amountToBurn);
    }

    function liquidate(
        address user,
        address collateralToken
    ) external override {
        address _msgSender = msg.sender;
        uint256 userVaultHealthFactor = getHealthFactor(user, collateralToken);

        require(
            userVaultHealthFactor < Math.ONE,
            Errors.VaultManager__HealthFactorIsNotBroken()
        );

        Vault storage vault = s_userVault[user][collateralToken];
        uint256 debtToCover = vault.SPIUSDMinted;
        uint256 amountCollateralSeized = vault.collateralDeposited;

        uint256 amountCollateralFromDebtCovered = getTokenAmountFromUsd(
            collateralToken,
            debtToCover
        );

        uint256 bonusCollateral = amountCollateralFromDebtCovered.mulDown(
            LIQUIDATION_BONUS
        );

        uint256 amountCollateralToLiquidator = amountCollateralFromDebtCovered +
            bonusCollateral;

        uint256 amountCollateralToTreasury = amountCollateralSeized -
            amountCollateralToLiquidator;

        _redeemCollateral(
            user,
            _msgSender,
            collateralToken,
            amountCollateralToLiquidator
        );
        _redeemCollateral(
            user,
            s_treasury,
            collateralToken,
            amountCollateralToTreasury
        );

        _burnSPIUSD(_msgSender, user, collateralToken, debtToCover);
    }

    function updateTreasury(address newTreasuryAddress) external onlyOwner {
        s_treasury = newTreasuryAddress;
    }

    /**
     * @notice Overrides renounceOwnership to prevent ownership renunciation
     * @dev This function is intentionally empty to block the ability to renounce ownership
     * since the Vault Manager requires ongoing management for adding supported collateral
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
        Vault storage vault = s_userVault[from][collateralToken];
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
        Vault storage vault = s_userVault[onBehalfOf][collateralToken];
        vault.SPIUSDMinted -= amountToBurn;

        SPIUSD.burn(burnFrom, amountToBurn);
    }

    function _revertIfExceedsMaxLTV(
        address user,
        address collateralToken
    ) internal view {
        require(
            _calcLTV(user, collateralToken, MAX_LTV) >= Math.ONE,
            Errors.VaultManager__MintExceedsMaxLTV()
        );
    }

    function _calcLTV(
        address user,
        address collateralToken,
        uint256 LTV
    ) internal view returns (uint256) {
        uint256 totalSPIUSDMinted = s_userVault[user][collateralToken]
            .SPIUSDMinted;

        uint256 totalCollateralValueInUsd = getUserVaultCollateralValue(
            user,
            collateralToken
        );

        uint256 collateralAdjustedForLtv = totalCollateralValueInUsd.mulDown(
            LTV
        );

        return collateralAdjustedForLtv.divDown(totalSPIUSDMinted);
    }

    /////////////////////////
    // External View Functions

    function getHealthFactor(
        address user,
        address collateralToken
    ) public view override returns (uint256) {
        return _calcLTV(user, collateralToken, LIQ_LTV);
    }

    function getUserVaultCollateralValue(
        address user,
        address collateralToken
    ) public view returns (uint256 totalCollateralValueInUsd) {
        uint256 amountCollateral = s_userVault[user][collateralToken]
            .collateralDeposited;
        return getTokenUsdValue(collateralToken, amountCollateral);
    }

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

    function getTokenAmountFromUsd(
        address token,
        uint256 usdAmountInWei
    ) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            s_priceFeeds[token]
        );

        (, int256 price, , , ) = priceFeed.latestRoundData();

        return (
            usdAmountInWei.divDown((uint256(price) * ADDITIONAL_FEED_PRECISION))
        );
    }
}
