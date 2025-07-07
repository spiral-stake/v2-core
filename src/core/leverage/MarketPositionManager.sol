// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import {IMorphoFlashLoanCallback} from "@morpho/interfaces/IMorphoCallbacks.sol";
import {IMorpho, MarketParams, Id} from "@morpho/interfaces/IMorpho.sol";
import {MorphoBalancesLib, SharesMathLib} from "@morpho/libraries/periphery/MorphoBalancesLib.sol";
import {TokenHelper} from "../libraries/TokenHelper.sol";
import {Error} from "../libraries/Errors.sol";

abstract contract MarketPositionManager is
    IMorphoFlashLoanCallback,
    TokenHelper
{
    using MorphoBalancesLib for IMorpho;
    using SharesMathLib for uint256;

    enum Action {
        LEVERAGE,
        UNLEVERAGE
    }

    /////////////////////////
    // Constants and Immutables

    IMorpho internal immutable i_morpho;

    /////////////////////////
    // Storage

    mapping(address collateralToken => MarketParams) internal s_marketParams;

    constructor(address morpho) {
        i_morpho = IMorpho(morpho);
    }

    /////////////////////////
    // External Functions

    function onMorphoFlashLoan(
        uint256 amountLoan,
        bytes memory data
    ) external override {
        require(
            msg.sender == address(i_morpho),
            Error.FlashLeverage__UntrustedLender()
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

    function _supplyCollateralAndBorrow(
        address collateralToken,
        uint256 amountCollateral,
        uint256 amountLoan
    ) internal returns (uint256 sharesBorrowed) {
        MarketParams memory marketParams = s_marketParams[collateralToken];

        _morphoSupplyCollateral(marketParams, amountCollateral);
        (, sharesBorrowed) = _morphoBorrow(marketParams, amountLoan);
    }

    function _repayAndWithdrawCollateral(
        address collateralToken,
        uint256 amountLoan,
        uint256 amountCollateral,
        uint256 sharesBorrowed
    ) internal {
        MarketParams memory marketParams = s_marketParams[collateralToken];

        _morphoRepay(marketParams, amountLoan, sharesBorrowed);
        _morphoWithdrawCollateral(marketParams, amountCollateral);
    }

    function _morphoSupplyCollateral(
        MarketParams memory marketParams,
        uint256 amount
    ) internal {
        _safeApprove(marketParams.collateralToken, address(i_morpho), amount);
        i_morpho.supplyCollateral(marketParams, amount, address(this), hex"");
    }

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
     *
     * @dev passed shares borrowed to burn the exact shares, to withdraw equivalent collateral
     * and safeApproved equivalent amount, but passed amount as 0 (Required by morpho)
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
            0, // AmountLoan
            sharesBorrowed,
            onBehalf,
            hex""
        );
    }

    function _morphoWithdrawCollateral(
        MarketParams memory marketParams,
        uint256 amount
    ) internal {
        address onBehalf = address(this);
        address receiver = address(this);

        i_morpho.withdrawCollateral(marketParams, amount, onBehalf, receiver);
    }

    function _updateMorphoMarket(
        address collateralToken,
        bytes32 morphoMarketId
    ) internal {
        s_marketParams[collateralToken] = i_morpho.idToMarketParams(
            Id.wrap(morphoMarketId)
        );
    }

    /////////////////////////
    // Virtual Functions, implemented in the main contract

    function _handleLeverage(
        uint256 amountLoan,
        bytes memory data
    ) internal virtual {}

    function _handleUnleverage(
        uint256 amountLoan,
        bytes memory data
    ) internal virtual {}

    /////////////////////////
    // Public View Functions

    function getRepayAmount(
        address collateralToken,
        uint256 sharesBorrowed
    ) public view returns (uint256 amountRepay) {
        MarketParams memory marketParams = s_marketParams[collateralToken];

        (, , uint256 totalBorrowAssets, uint256 totalBorrowShares) = i_morpho
            .expectedMarketBalances(marketParams);

        return sharesBorrowed.toAssetsUp(totalBorrowAssets, totalBorrowShares);
    }
}
