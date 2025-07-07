// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import {SwapAggregator, SwapParams, SwapData, ApproxParams, LimitOrderData} from "./SwapAggregator.sol";
import {MarketPositionManager, MarketParams, Id} from "./MarketPositionManager.sol";
import {LeveragePosition} from "../structs/LeveragePosition.sol";
import {CollateralTokenConfig} from "../structs/CollateralTokenConfig.sol";
import {IOracleRouter} from "../../interfaces/IOracleRouter.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import {Math} from "../libraries/Math.sol";
import {Error} from "../libraries/Errors.sol";

/**
 * @notice Loan token is currently fixed to USDC
 */

contract FlashLeverage is SwapAggregator, MarketPositionManager, Ownable2Step {
    using Math for uint256;

    /////////////////////////
    // Constants and Immutables

    // USD as the quote assets in price feeds
    address public constant USD = 0x0000000000000000000000000000000000000348;
    uint256 public constant LIQUIDATION_BUFFER = 50e15; // 5%, as 100% => 1e18
    uint256 public constant AMOUNT_COLLATERAL_CAP = 100e18;

    IOracleRouter public immutable i_oracleRouter;

    /////////////////////////
    // Storage

    mapping(address user => LeveragePosition[]) private s_userLeveragePositions;

    /////////////////////////
    // Events

    event LeveragePositionOpened(
        address indexed user,
        uint256 indexed positionId,
        address collateralToken,
        address loanToken,
        uint256 amountUserCollateral,
        uint256 amountTotalCollateral,
        uint256 sharesBorrowed
    );

    event LeveragePositionClosed(
        address indexed user,
        uint256 indexed positionId,
        uint256 indexed amountReturned
    );

    event CollateralTokenAdded(
        address indexed token,
        address indexed pendleMarket,
        bytes32 indexed morphoMarketId
    );

    /////////////////////////
    // Modifiers

    modifier validateAmountCollateral(uint256 value) {
        require(
            value > 0 && value <= AMOUNT_COLLATERAL_CAP,
            Error.FlashLeverage__InvalidAmountCollateral()
        );
        _;
    }

    /////////////////////////
    // Constructor

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

    function leverage(
        address onBehalfOf,
        address collateralToken,
        uint256 amountCollateral,
        uint256 desiredLtv,
        address pendleSwap,
        SwapData memory swapData,
        ApproxParams memory approxParams
    ) external validateAmountCollateral(amountCollateral) {
        require(
            desiredLtv <= getMaxLtv(collateralToken),
            Error.FlashLeverage__ExceedsMaxLeverageLTV()
        );
        address loanToken = s_marketParams[collateralToken].loanToken;
        require(
            loanToken != address(0),
            Error.FlashLeverage__UnsupportedCollateralToken()
        );

        _transferIn(collateralToken, msg.sender, amountCollateral);

        uint256 amountLoan = calcLoanAmount(
            collateralToken,
            loanToken,
            amountCollateral,
            desiredLtv
        );

        uint256 positionId = s_userLeveragePositions[onBehalfOf].length;
        s_userLeveragePositions[onBehalfOf].push(
            LeveragePosition({
                collateralToken: collateralToken,
                loanToken: loanToken,
                amountUserCollateral: amountCollateral,
                amountTotalCollateral: 0, // gets set in _handleLeverage
                sharesBorrowed: 0 // gets set in _handleLeverage
            })
        );

        bytes memory data = abi.encode(
            Action.LEVERAGE,
            onBehalfOf,
            positionId,
            pendleSwap,
            swapData,
            approxParams
        );

        i_morpho.flashLoan(loanToken, amountLoan, data);
    }

    function unleverage(
        uint256 positionId,
        address pendleSwap,
        SwapData memory swapData,
        LimitOrderData memory limitOrderData
    ) external {
        address _msgSender = msg.sender;

        require(
            positionId < s_userLeveragePositions[_msgSender].length,
            Error.FlashLeverage__PositionDoesNotExist()
        );
        LeveragePosition memory position = s_userLeveragePositions[_msgSender][
            positionId
        ];
        require(
            position.loanToken != address(0),
            Error.FlashLeverage__PositionAlreadyUnleveraged()
        );

        bytes memory data = abi.encode(
            Action.UNLEVERAGE,
            _msgSender,
            positionId,
            pendleSwap,
            swapData,
            limitOrderData
        );

        uint256 amountLoan = getRepayAmount(
            position.collateralToken,
            position.sharesBorrowed
        );

        i_morpho.flashLoan(position.loanToken, amountLoan, data);

        delete s_userLeveragePositions[_msgSender][positionId];
    }

    /////////////////////////
    // Internal Functions

    function _handleLeverage(
        uint256 amountLoan,
        bytes memory data
    ) internal override {
        (
            ,
            address user,
            uint256 positionId,
            address pendleSwap,
            SwapData memory swapData,
            ApproxParams memory approxParams
        ) = abi.decode(
                data,
                (Action, address, uint256, address, SwapData, ApproxParams)
            );

        LeveragePosition storage position = s_userLeveragePositions[user][
            positionId
        ];

        // Swap USDC loan -> PT collateral
        uint256 amountSwappedCollateralToken = _swapLoanTokenToCollateralToken(
            position.loanToken,
            position.collateralToken,
            amountLoan,
            pendleSwap,
            swapData,
            approxParams
        );
        position.amountTotalCollateral =
            position.amountUserCollateral +
            amountSwappedCollateralToken;

        // Supply total collateral and borrow USDC
        uint256 sharesBorrowed = _supplyCollateralAndBorrow(
            position.collateralToken,
            position.amountTotalCollateral,
            amountLoan
        );
        position.sharesBorrowed = sharesBorrowed;

        // Repay the flash loan, with borrowed USDC
        _forceApprove(position.loanToken, address(i_morpho), amountLoan);

        emit LeveragePositionOpened(
            user,
            positionId,
            position.collateralToken,
            position.loanToken,
            position.amountUserCollateral,
            position.amountTotalCollateral,
            position.sharesBorrowed
        );
    }

    function _handleUnleverage(
        uint256 amountLoan,
        bytes memory data
    ) internal override {
        (
            ,
            address user,
            uint256 positionId,
            address pendleSwap,
            SwapData memory swapData,
            LimitOrderData memory limitOrderData
        ) = abi.decode(
                data,
                (Action, address, uint256, address, SwapData, LimitOrderData)
            );

        LeveragePosition storage position = s_userLeveragePositions[user][
            positionId
        ];

        // Repay the loan, with flashloan amount, to withdraw position's total collateral
        _repayAndWithdrawCollateral(
            position.collateralToken,
            amountLoan,
            position.amountTotalCollateral,
            position.sharesBorrowed
        );

        // Swap withdrawn total collateral -> USDC
        uint256 amountSwappedLoanToken = _swapCollateralTokenToLoanToken(
            position.collateralToken,
            position.loanToken,
            position.amountTotalCollateral,
            pendleSwap,
            swapData,
            limitOrderData
        );

        // Repay the flash loan, with swapped USDC
        _forceApprove(position.loanToken, address(i_morpho), amountLoan);

        // And transfer out the remaining USDC to the user
        uint256 amountReturned;
        if (amountSwappedLoanToken > amountLoan) {
            amountReturned = amountSwappedLoanToken - amountLoan;
            _transferOut(position.loanToken, user, amountReturned);
        }

        emit LeveragePositionClosed(user, positionId, amountReturned);
    }

    function addSupportedCollateralTokens(
        CollateralTokenConfig[] memory configs
    ) external onlyOwner {
        for (uint256 i = 0; i < configs.length; i++) {
            CollateralTokenConfig memory config = configs[i];

            _updateMorphoMarket(config.token, config.morphoMarketId);
            _updateSwapParams(
                config.token,
                SwapParams({
                    underlyingToken: config.underlyingToken,
                    pendleMarket: config.pendleMarket
                })
            );

            emit CollateralTokenAdded(
                config.token,
                config.pendleMarket,
                config.morphoMarketId
            );
        }
    }

    /////////////////////////
    // Public and External View Functions

    /**
     * @dev Internal function to calculate flash loan amount based on user's collateral and Ltv
     * @param collateralToken The token being used as collateral
     * @param loanToken The token being user to provide loan
     * @param userCollateralAmount Amount of collateral supplied by user
     * @return amountToBorrow stblUSD amount to borrow
     *
     * @notice Important, here we roughly assume that USDC, USDT (loanToken) value is always $1
     */
    function calcLoanAmount(
        address collateralToken,
        address loanToken,
        uint256 userCollateralAmount,
        uint256 desiredLtv
    ) public view returns (uint256) {
        uint256 userCollateralInUsd = getTokenUsdValue(
            collateralToken,
            userCollateralAmount
        );

        // Total position value in USD = collateralUsd / (1 - LTV)
        uint256 totalPositionUsd = userCollateralInUsd.divDown(
            Math.ONE - desiredLtv
        );

        // Loan amount = total position - collateral
        uint256 loanUsd = totalPositionUsd - userCollateralInUsd;

        // Adjust loan amount to match loanToken decimals
        return loanUsd.scaleTo(18, IERC20Metadata(loanToken).decimals());
    }

    /**
     *
     * @dev return value is 18 decimals
     */
    function getTokenUsdValue(
        address token,
        uint256 amount
    ) public view returns (uint256) {
        return i_oracleRouter.getQuote(amount, token, USD);
    }

    function getMaxLtv(address collateralToken) public view returns (uint256) {
        return s_marketParams[collateralToken].lltv - LIQUIDATION_BUFFER;
    }

    function getUserLeveragePositions(
        address user
    ) external view returns (LeveragePosition[] memory) {
        return s_userLeveragePositions[user];
    }

    function getUserLeveragePosition(
        address user,
        uint256 positionId
    ) external view returns (LeveragePosition memory) {
        return s_userLeveragePositions[user][positionId];
    }
}
