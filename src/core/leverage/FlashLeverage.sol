// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import {IMorpho, MarketParams, Id, Position} from "@morpho/interfaces/IMorpho.sol";
import {MorphoLib} from "@morpho/libraries/periphery/MorphoLib.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {TokenHelper} from "../libraries/TokenHelper.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {IMorphoFlashLoanCallback} from "@morpho/interfaces/IMorphoCallbacks.sol";
import {IPAllActionV3} from "@pendle/core-v2/contracts/interfaces/IPAllActionV3.sol";
import {IPMarket} from "@pendle/core-v2/contracts/interfaces/IPMarket.sol";
import {Errors} from "../libraries/Errors.sol";
import {Math} from "../libraries/Math.sol";
import {IOracleRouter} from "../../interfaces/IOracleRouter.sol";
import {PendleParams} from "../structs/PendleParams.sol";
import {LeveragePosition} from "../structs/LeveragePosition.sol";
import "./SwapAggregator.sol";

import {console} from "forge-std/console.sol";

contract FlashLeverage is
    IMorphoFlashLoanCallback,
    SwapAggregator,
    TokenHelper,
    Ownable2Step
{
    using Math for uint256;

    enum Action {
        LEVERAGE,
        UNLEVERAGE
    }

    /////////////////////////
    // Constants and Immutables

    // USD as the quote assets in price feeds
    address private constant USD = 0x0000000000000000000000000000000000000348;
    uint256 private constant LIQUIDATION_BUFFER = 25e15; // 2.5%, as 100% => 1e18

    IMorpho private immutable i_morpho;
    IPAllActionV3 private immutable i_pendleRouter;
    IOracleRouter private immutable i_oracleRouter;

    /////////////////////////
    // Storage

    mapping(address collateralToken => MarketParams) private s_morphoParams;
    mapping(address collateralToken => PendleParams) private s_pendleParams;
    mapping(address user => LeveragePosition[]) private s_userLeveragePositions;

    constructor(
        address morphoAddress,
        address pendleRouter,
        address oracleRouter
    ) Ownable(msg.sender) {
        i_morpho = IMorpho(morphoAddress);
        i_pendleRouter = IPAllActionV3(pendleRouter);
        i_oracleRouter = IOracleRouter(oracleRouter);
    }

    function leverage(
        address onBehalfOf,
        address collateralToken,
        uint256 amountCollateral,
        uint256 desiredLtv,
        ApproxParams memory approxParams,
        address pendleSwap,
        SwapData memory swapData
    ) external {
        MarketParams memory morphoParams = s_morphoParams[collateralToken];
        require(
            desiredLtv <= getMaxLtv(collateralToken),
            Errors.FlashLeverage__ExceedsMaxLeverageLTV()
        );

        _transferIn(collateralToken, msg.sender, amountCollateral);

        uint8 loanTokenDecimals = IERC20Metadata(morphoParams.loanToken)
            .decimals();

        uint256 amountLoan = calcLoanAmount(
            collateralToken,
            amountCollateral,
            desiredLtv
        ).scaleTo(18, loanTokenDecimals);

        bytes memory data = abi.encode(
            Action.LEVERAGE,
            onBehalfOf,
            collateralToken,
            amountCollateral,
            approxParams,
            pendleSwap,
            swapData
        );

        i_morpho.flashLoan(morphoParams.loanToken, amountLoan, data);

        s_userLeveragePositions[msg.sender].push(
            LeveragePosition({
                collateralToken: collateralToken,
                amountUserCollateral: amountCollateral,
                ltv: desiredLtv
            })
        );
    }

    function unleverage(
        uint256 leveragePositionId,
        ApproxParams memory approxParams,
        address pendleSwap,
        SwapData memory swapData
    ) external {
        LeveragePosition memory leveragePosition = s_userLeveragePositions[
            msg.sender
        ][leveragePositionId];

        MarketParams memory morphoParams = s_morphoParams[
            leveragePosition.collateralToken
        ];

        bytes memory data = abi.encode(
            Action.UNLEVERAGE,
            msg.sender,
            leveragePositionId,
            leveragePosition.collateralToken,
            leveragePosition.amountUserCollateral
        );

        delete s_userLeveragePositions[msg.sender][leveragePositionId];

        i_morpho.flashLoan(morphoParams.loanToken, 12, data); // Amount Loan needs to change and Is incomplete function
    }

    function onMorphoFlashLoan(
        uint256 amountLoan,
        bytes memory data
    ) external override {
        require(msg.sender == address(i_morpho));

        (
            Action action,
            address onBehalfOf,
            address collateralToken,
            uint256 amountUserCollateral,
            ApproxParams memory approxParams,
            address pendleSwap,
            SwapData memory swapData
        ) = abi.decode(
                data,
                (
                    Action,
                    address,
                    address,
                    uint256,
                    ApproxParams,
                    address,
                    SwapData
                )
            );

        PendleParams memory pendleParams = s_pendleParams[collateralToken];
        MarketParams memory morphoParams = s_morphoParams[collateralToken];

        if (action == Action.LEVERAGE) {
            _handleLeverage(
                onBehalfOf,
                morphoParams,
                pendleParams,
                amountUserCollateral,
                amountLoan,
                approxParams,
                pendleSwap,
                swapData
            );
        } else {}

        _safeApprove(morphoParams.loanToken, address(i_morpho), amountLoan);
    }

    /////////////////////////
    // Internal Functions

    function _handleLeverage(
        address onBehalfOf,
        MarketParams memory morphoParams,
        PendleParams memory pendleParams,
        uint256 amountUserCollateral,
        uint256 amountLoan,
        ApproxParams memory approxParams,
        address pendleSwap,
        SwapData memory swapData
    ) internal {
        // Swap USDC loan -> PT collateral
        _safeApprove(
            morphoParams.loanToken,
            address(i_pendleRouter),
            amountLoan
        );
        (uint256 amountSwappedCollateral, , ) = i_pendleRouter
            .swapExactTokenForPt(
                address(this),
                pendleParams.market,
                0,
                approxParams,
                createTokenInputSimple(
                    morphoParams.loanToken,
                    amountLoan,
                    pendleParams.underlyingToken,
                    pendleSwap,
                    swapData
                ),
                createEmptyLimitOrderData()
            );

        uint256 amountTotalCollateral = amountUserCollateral +
            amountSwappedCollateral;

        // Supply total collateral to amount Loan USDC against collateral PT
        _morphoSupplyCollateral(morphoParams, amountTotalCollateral);
        _morphoBorrow(morphoParams, amountLoan);
    }

    function _handleUnleverage(
        address onBehalfOf,
        MarketParams memory morphoParams,
        PendleParams memory pendleParams,
        uint256 amountCollateral,
        uint256 amountLoan
    ) internal {}

    function _morphoSupplyCollateral(
        MarketParams memory morphoParams,
        uint256 amount
    ) internal {
        address onBehalfOf = msg.sender;

        _safeApprove(morphoParams.collateralToken, address(i_morpho), amount);
        i_morpho.supplyCollateral(morphoParams, amount, address(this), hex"");
    }

    function _morphoBorrow(
        MarketParams memory morphoParams,
        uint256 amount
    ) internal returns (uint256 assetsBorrowed, uint256 sharesBorrowed) {
        uint256 shares;
        address onBehalf = address(this);
        address receiver = address(this);

        (assetsBorrowed, sharesBorrowed) = i_morpho.borrow(
            morphoParams,
            amount,
            shares,
            onBehalf,
            receiver
        );
    }

    function addSupportedCollateralToken(
        address collateralToken,
        bytes32 morphoMarketId,
        PendleParams memory pendleParams
    ) external onlyOwner {
        s_morphoParams[collateralToken] = i_morpho.idToMarketParams(
            Id.wrap(morphoMarketId)
        );
        s_pendleParams[collateralToken] = pendleParams;
    }

    /**
     * @dev Internal function to calculate flash loan amount based on user's collateral and Ltv
     * @param collateralToken The token being used as collateral
     * @param userCollateralAmount Amount of collateral supplied by user
     * @param ltv Desired Loan-To-Value ratio (1e18 precision)
     * @return amountToBorrow stblUSD amount to borrow
     * @notice Important, here we roughly assume that USDC, USDT (loanToken) value is $1
     */
    function calcLoanAmount(
        address collateralToken,
        uint256 userCollateralAmount,
        uint256 ltv
    ) public view returns (uint256) {
        uint256 userCollateralInUsd = getTokenUsdValue(
            collateralToken,
            userCollateralAmount
        );

        uint256 loanAmount = Math.ONE.mulDown(userCollateralInUsd).divDown(
            Math.ONE - ltv
        );

        return loanAmount - userCollateralInUsd;
    }

    function getTokenUsdValue(
        address token,
        uint256 amount
    ) public view returns (uint256) {
        return i_oracleRouter.getQuote(amount, token, USD);
    }

    function getMaxLtv(address collateralToken) public view returns (uint256) {
        return s_morphoParams[collateralToken].lltv - LIQUIDATION_BUFFER;
    }

    function getUserLeveragePositions(
        address user
    ) external view returns (LeveragePosition[] memory) {
        return s_userLeveragePositions[user];
    }
}
