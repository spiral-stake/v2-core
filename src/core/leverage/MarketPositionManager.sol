// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

/// @title MarketPositionManager Abstract Contract
/// @notice Handles core collateral and borrowing logic using the Morpho protocol.
/// @dev This contract must be inherited and extended with leverage/unleverage logic.
///      Integrates Morpho flashloans, supply/borrow/repay/withdraw flows, and market configuration.

import {IMorphoFlashLoanCallback} from "@morpho/interfaces/IMorphoCallbacks.sol";
import {IMorpho, MarketParams, Id} from "@morpho/interfaces/IMorpho.sol";
import {IOracle} from "@morpho/interfaces/IOracle.sol";
import {MorphoBalancesLib, SharesMathLib} from "@morpho/libraries/periphery/MorphoBalancesLib.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import {TokenHelper} from "../libraries/TokenHelper.sol";
import {FLCError} from "../libraries/Error.sol";

abstract contract MarketPositionManager is
    IMorphoFlashLoanCallback,
    TokenHelper
{
    using MorphoBalancesLib for IMorpho;
    using SharesMathLib for uint256;

    /// @notice Enum defining available flashloan actions.
    enum Action {
        LEVERAGE,
        UNLEVERAGE
    }

    /////////////////////////
    // Constants and Immutables

    IMorpho public immutable i_morpho;

    /////////////////////////
    // Storage

    mapping(address collateralToken => mapping(address loanToken => MarketParams))
        internal s_marketParams;

    mapping(address loanToken => uint8) internal s_loanTokenDecimals;

    /////////////////////////
    // Constructor

    /// @param morpho Address of the deployed Morpho contract.
    constructor(address morpho) {
        i_morpho = IMorpho(morpho);
    }

    /////////////////////////
    // External Functions

    /**
     * @notice Morpho flashloan callback handler.
     * @dev Delegates handling to either _handleLeverage or _handleUnleverage based on Action enum.
     * @param amountLoan Amount of flashloan received.
     * @param data Encoded data used to determine action and pass parameters.
     */
    function onMorphoFlashLoan(
        uint256 amountLoan,
        bytes calldata data
    ) external override {
        require(
            msg.sender == address(i_morpho),
            FLCError.FlashLeverageCore__UntrustedLender()
        );

        Action action = abi.decode(data, (Action));

        if (action == Action.LEVERAGE) {
            _handleLeverage(amountLoan, data);
        } else {
            _handleUnleverage(amountLoan, data);
        }
    }

    /////////////////////////
    // Internal Functions

    /**
     * @notice Supplies collateral and borrows funds from Morpho market.
     * @param collateralToken Token used as collateral.
     * @param amountCollateral Amount of collateral to supply.
     * @param amountLoan Amount to borrow.
     * @return sharesBorrowed Number of shares borrowed from the market.
     */
    function _supplyCollateralAndBorrow(
        address collateralToken,
        address loanToken,
        uint256 amountCollateral,
        uint256 amountLoan
    ) internal returns (uint256 sharesBorrowed) {
        MarketParams memory marketParams = s_marketParams[collateralToken][
            loanToken
        ];

        _morphoSupplyCollateral(marketParams, amountCollateral);
        (, sharesBorrowed) = _morphoBorrow(marketParams, amountLoan);
    }

    /**
     * @notice Repays borrowed funds and withdraws supplied collateral.
     * @param collateralToken Token used as collateral.
     * @param amountLoan Amount of loan to repay (for approval).
     * @param amountCollateral Amount of collateral to withdraw.
     * @param sharesBorrowed Shares representing borrowed amount to repay.
     */
    function _repayAndWithdrawCollateral(
        address collateralToken,
        address loanToken,
        uint256 amountLoan,
        uint256 amountCollateral,
        uint256 sharesBorrowed
    ) internal {
        MarketParams memory marketParams = s_marketParams[collateralToken][
            loanToken
        ];

        _morphoRepay(marketParams, amountLoan, sharesBorrowed);
        _morphoWithdrawCollateral(marketParams, amountCollateral);
    }

    /**
     * @notice Supplies collateral into a Morpho market.
     * @param marketParams Market configuration details.
     * @param amount Amount of collateral to supply.
     */
    function _morphoSupplyCollateral(
        MarketParams memory marketParams,
        uint256 amount
    ) internal {
        _safeApprove(marketParams.collateralToken, address(i_morpho), amount);
        i_morpho.supplyCollateral(marketParams, amount, address(this), hex"");
    }

    /**
     * @notice Borrows funds from a Morpho market.
     * @param marketParams Market configuration details.
     * @param amount Amount to borrow in asset terms.
     * @return assetsBorrowed Amount actually borrowed.
     * @return sharesBorrowed Shares received for the borrowed amount.
     */
    function _morphoBorrow(
        MarketParams memory marketParams,
        uint256 amount
    ) internal returns (uint256 assetsBorrowed, uint256 sharesBorrowed) {
        uint256 shares;
        address onBehalf = address(this);
        address receiver = address(this);

        (assetsBorrowed, sharesBorrowed) = i_morpho.borrow(
            marketParams,
            amount,
            shares,
            onBehalf,
            receiver
        );
    }

    /**
     * @notice Repays borrowed shares to Morpho market.
     * @dev Repays exact shares, sets amount=0 as required by Morpho, but approves full amount.
     * @param marketParams Market configuration details.
     * @param amount Stablecoin value of repayment (used only for approval).
     * @param sharesBorrowed Shares to repay.
     * @return assetsRepaid Actual assets repaid.
     * @return sharesRepaid Shares repaid.
     */
    function _morphoRepay(
        MarketParams memory marketParams,
        uint256 amount,
        uint256 sharesBorrowed
    ) internal returns (uint256 assetsRepaid, uint256 sharesRepaid) {
        _forceApprove(marketParams.loanToken, address(i_morpho), amount);

        address onBehalf = address(this);
        (assetsRepaid, sharesRepaid) = i_morpho.repay(
            marketParams,
            0, // amount ignored when repaying by shares
            sharesBorrowed,
            onBehalf,
            hex""
        );
    }

    /**
     * @notice Withdraws previously supplied collateral from Morpho.
     * @param marketParams Market configuration details.
     * @param amount Amount of collateral to withdraw.
     */
    function _morphoWithdrawCollateral(
        MarketParams memory marketParams,
        uint256 amount
    ) internal {
        address onBehalf = address(this);
        address receiver = address(this);

        i_morpho.withdrawCollateral(marketParams, amount, onBehalf, receiver);
    }

    /**
     * @notice Updates market parameters for a collateral token using Morpho's market ID.
     * @param params Morpho market params for PT collateral token
     */
    function _updateMarketParams(MarketParams memory params) internal {
        s_marketParams[params.collateralToken][params.loanToken] = params;
        s_loanTokenDecimals[params.loanToken] = IERC20Metadata(params.loanToken)
            .decimals();
    }

    /////////////////////////
    // Virtual Functions, implemented in the main contract

    /**
     * @dev Called after receiving a flashloan for leverage operation.
     * @param amountLoan Amount of flashloan received.
     * @param data Encoded context for leverage.
     */
    function _handleLeverage(
        uint256 amountLoan,
        bytes calldata data
    ) internal virtual {}

    /**
     * @dev Called after receiving a flashloan for unleverage operation.
     * @param amountLoan Amount of flashloan received.
     * @param data Encoded context for unleverage.
     */
    function _handleUnleverage(
        uint256 amountLoan,
        bytes calldata data
    ) internal virtual {}

    /////////////////////////
    // Public View Functions

    /**
     * @notice Calculates the amount of loan token needed to repay borrowed shares.
     * @param collateralToken Token used as collateral in the position.
     * @param sharesBorrowed Shares representing the borrowed position.
     * @return amountRepay Equivalent amount in loan token required for repayment.
     */
    function getSharesToAsset(
        address collateralToken,
        address loanToken,
        uint256 sharesBorrowed
    ) public view returns (uint256 amountRepay) {
        MarketParams memory marketParams = s_marketParams[collateralToken][
            loanToken
        ];

        (, , uint256 totalBorrowAssets, uint256 totalBorrowShares) = i_morpho
            .expectedMarketBalances(marketParams);

        return sharesBorrowed.toAssetsUp(totalBorrowAssets, totalBorrowShares);
    }
}
