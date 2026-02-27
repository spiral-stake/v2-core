// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

/// @title MarketPositionManager Abstract Contract
/// @notice Handles core collateral and borrowing logic using the Morpho protocol.
/// @dev This contract must be inherited and extended with leverage/deleverage logic.
/// Integrates Morpho flashloans, supply/borrow/repay/withdraw flows, and market configuration.

import {IMorphoFlashLoanCallback} from "@morpho/interfaces/IMorphoCallbacks.sol";
import {IMorpho, MarketParams, Id, Position} from "@morpho/interfaces/IMorpho.sol";
import {MorphoBalancesLib, SharesMathLib} from "@morpho/libraries/periphery/MorphoBalancesLib.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import {TokenHelper} from "../libraries/TokenHelper.sol";
import {FLError} from "../libraries/Error.sol";
import {Math} from "../libraries/Math.sol";
import {UserProxy} from "./UserProxy.sol";

abstract contract MarketPositionManager is
    IMorphoFlashLoanCallback,
    TokenHelper
{
    using Math for uint256;
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

    mapping(bytes32 marketId => MarketParams) internal s_markets;

    // Cached Loan Token Decimals to save gas by reducing external calls
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
     * @dev Delegates handling to either _handleLeverage or _handleDeleverage based on Action enum.
     * @param amountLoan Amount of flashloan received.
     * @param data Encoded data used to determine action and pass parameters.
     */
    function onMorphoFlashLoan(
        uint256 amountLoan,
        bytes calldata data
    ) external override {
        require(
            msg.sender == address(i_morpho),
            FLError.FlashLeverage__UntrustedLender()
        );

        Action action = abi.decode(data, (Action));

        if (action == Action.LEVERAGE) {
            _handleLeverage(amountLoan, data);
        } else {
            _handleDeleverage(amountLoan, data);
        }
    }

    /////////////////////////
    // Internal Functions

    /**
     * @notice Supplies collateral and borrows funds from Morpho market.
     * @param userProxy Address of the user's proxy contract, to execute / deposit on behalf of
     * @param market Market parameters for the collateral-loan token pair.
     * @param amountCollateral Amount of collateral to supply.
     * @param amountBorrow Amount to borrow.
     * @return borrowShares Number of shares borrowed from the market.
     */
    function _supplyCollateralAndBorrowViaProxy(
        address userProxy,
        MarketParams memory market,
        uint256 amountCollateral,
        uint256 amountBorrow
    ) internal returns (uint256 borrowShares) {
        _morphoSupplyCollateral(userProxy, market, amountCollateral);
        borrowShares = _morphoBorrowViaProxy(userProxy, market, amountBorrow);
    }

    /**
     * @notice Repays borrowed funds and withdraws supplied collateral.
     * @param userProxy Address of the user's proxy contract, to execute / deposit on behalf of
     * @param market Market parameters for the collateral-loan token pair.
     * @param amountLoan Amount of loan to repay (for approval).
     * @param amountCollateral Amount of collateral to withdraw.
     * @param borrowShares Shares representing borrowed amount to repay.
     */
    function _repayAndWithdrawCollateralViaProxy(
        address userProxy,
        MarketParams memory market,
        uint256 amountLoan,
        uint256 amountCollateral,
        uint256 borrowShares
    ) internal {
        _morphoRepay(userProxy, market, amountLoan, borrowShares);
        _morphoWithdrawCollateralViaProxy(userProxy, market, amountCollateral);
    }

    /**
     * @notice Supplies collateral into a Morpho market.
     * @param userProxy Address of the user's proxy contract, to supply on behalf of
     * @param marketParams Market configuration details.
     * @param amount Amount of collateral to supply.
     */
    function _morphoSupplyCollateral(
        address userProxy,
        MarketParams memory marketParams,
        uint256 amount
    ) internal {
        if (amount > 0) {
            address onBehalfOf = userProxy;

            _forceApprove(
                marketParams.collateralToken,
                address(i_morpho),
                amount
            );
            i_morpho.supplyCollateral(marketParams, amount, onBehalfOf, hex"");
        }
    }

    /**
     * @notice Borrows funds from a Morpho market.
     * @param userProxy Address of the user's proxy contract, to execute borrow
     * @param marketParams Market configuration details.
     * @param amount Amount to borrow in asset terms.
     * @return borrowShares Shares received for the borrowed amount.
     */
    function _morphoBorrowViaProxy(
        address userProxy,
        MarketParams memory marketParams,
        uint256 amount
    ) internal returns (uint256 borrowShares) {
        if (amount > 0) {
            uint256 shares;
            address onBehalf = userProxy;
            address receiver = address(this);

            bytes memory result = UserProxy(userProxy).execute(
                abi.encodeWithSignature(
                    "borrow((address,address,address,address,uint256),uint256,uint256,address,address)",
                    marketParams,
                    amount,
                    shares,
                    onBehalf,
                    receiver
                )
            );

            (, borrowShares) = abi.decode(result, (uint256, uint256));
        }
    }

    /**
     * @notice Repays borrowed shares to Morpho market.
     * @dev When repaying by shares, amount must be 0 per Morpho's interface.
     *      When repaying by amount, shares must be 0. Full amount is approved for safety margin.
     * @param userProxy Address of the user's proxy contract, to repay on behalf of
     * @param marketParams Market configuration details.
     * @param amount Stablecoin value of repayment (used only for approval).
     * @param borrowShares Shares to repay.
     * @return assetsRepaid Actual assets repaid.
     * @return sharesRepaid Shares repaid.
     */
    function _morphoRepay(
        address userProxy,
        MarketParams memory marketParams,
        uint256 amount,
        uint256 borrowShares
    ) internal returns (uint256 assetsRepaid, uint256 sharesRepaid) {
        if (amount > 0) {
            _forceApprove(marketParams.loanToken, address(i_morpho), amount);

            address onBehalf = userProxy;
            (assetsRepaid, sharesRepaid) = i_morpho.repay(
                marketParams,
                borrowShares == 0 ? amount : 0,
                borrowShares,
                onBehalf,
                hex""
            );
        }
    }

    /**
     * @notice Withdraws previously supplied collateral from Morpho.
     * @param userProxy Address of the user's proxy contract, to execute withdrawCollateral
     * @param marketParams Market configuration details.
     * @param amount Amount of collateral to withdraw.
     */
    function _morphoWithdrawCollateralViaProxy(
        address userProxy,
        MarketParams memory marketParams,
        uint256 amount
    ) internal {
        if (amount > 0) {
            address onBehalf = userProxy;
            address receiver = address(this);

            UserProxy(userProxy).execute(
                abi.encodeWithSignature(
                    "withdrawCollateral((address,address,address,address,uint256),uint256,address,address)",
                    marketParams,
                    amount,
                    onBehalf,
                    receiver
                )
            );
        }
    }

    /**
     * @notice Updates market parameters for a given Morpho market.
     * @param marketId Morpho market id to store the parameters against.
     * @param market Morpho market parameters to store.
     */
    function _updateMarket(
        bytes32 marketId,
        MarketParams memory market
    ) internal {
        s_markets[marketId] = market;
        s_loanTokenDecimals[market.loanToken] = IERC20Metadata(market.loanToken)
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
     * @dev Called after receiving a flashloan for deleverage operation.
     * @param amountLoan Amount of flashloan received.
     * @param data Encoded context for deleverage.
     */
    function _handleDeleverage(
        uint256 amountLoan,
        bytes memory data
    ) internal virtual {}

    /////////////////////////
    // Public View Functions

    /**
     * @notice Retrieves the Morpho position for a user in a specific market.
     * @param user The address of the user (typically a UserProxy contract).
     * @param market Market parameters used to derive the market id.
     * @return Position struct containing collateral amount and borrow shares.
     */
    function getMorphoPosition(
        address user,
        MarketParams memory market
    ) public view returns (Position memory) {
        return i_morpho.position(Id.wrap(keccak256(abi.encode(market))), user);
    }

    /**
     * @notice Calculates the amount of loan token needed to repay borrowed shares.
     * @param market Market parameters for the collateral-loan token pair.
     * @param borrowShares Shares representing the borrowed position.
     * @return Equivalent amount in loan token (using the token's native decimals).
     */
    function getSharesValueInLoanToken(
        MarketParams memory market,
        uint256 borrowShares
    ) public view returns (uint256) {
        (, , uint256 totalBorrowAssets, uint256 totalBorrowShares) = i_morpho
            .expectedMarketBalances(market);

        return borrowShares.toAssetsUp(totalBorrowAssets, totalBorrowShares);
    }
}
