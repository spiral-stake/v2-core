// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import {IPAllActionV3, ApproxParams, TokenInput, TokenOutput, SwapData, LimitOrderData, SwapType, FillOrderParams} from "@pendle/core-v2/contracts/interfaces/IPAllActionV3.sol";
import {IFlashLeverage} from "../interfaces/IFlashLeverage.sol";
import {LeverageParams} from "../core/structs/LeverageParams.sol";
import {SwapParams} from "../core/structs/SwapParams.sol";
import {TokenHelper, IERC20} from "../core/libraries/TokenHelper.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";

/**
 * @title FlashLeverageWrapper
 * @notice A wrapper contract that enables leveraged positions using flash loans with automatic token swapping
 * @dev This contract acts as an intermediary between users and the flash leverage system, handling token swaps via Pendle
 */

/**
 * @notice Parameters required for executing a leveraged position
 * @param tokenIn The input token provided by the user
 * @param amountTokenIn Amount of input tokens to use
 * @param minCollateralOut Minimum amount of collateral tokens expected from swap
 * @param approxParams Parameters for approximation algorithms in Pendle
 * @param pendleSwap Address of the Pendle swap router
 * @param swapData Encoded swap data for token routing
 * @param limitOrderData Parameters for limit order execution
 */
struct LeverageWrapperParams {
    address tokenIn;
    uint256 amountTokenIn;
    uint256 minCollateralOut;
    ApproxParams approxParams;
    address pendleSwap;
    SwapData swapData;
    LimitOrderData limitOrderData;
}

contract FlashLeverageWrapper is TokenHelper, Ownable2Step {
    /////////////////////////
    // Constants and Immutables

    /// @notice Pendle router for executing token swaps
    IPAllActionV3 public immutable i_pendleRouter;

    /// @notice Flash leverage contract for executing leveraged positions
    IFlashLeverage public immutable i_flashLeverage;

    /////////////////////////
    // Storage

    /// @notice Mapping of collateral tokens to their swap parameters
    mapping(address collateralToken => SwapParams) private s_swapParams;

    /////////////////////////
    // Errors

    error FlashLeverageWrapper__InvalidAmountTokenIn();
    error FlashLeverageWrapper__UnsupportedCollateralToken();

    /////////////////////////
    // Modifiers

    /**
     * @notice Validates that the provided amount is greater than zero
     * @param value The amount to validate
     */
    modifier validateAmount(uint256 value) {
        require(value > 0, FlashLeverageWrapper__InvalidAmountTokenIn());
        _;
    }

    /////////////////////////
    // Constructor

    /**
     * @notice Initializes the wrapper with required contract addresses
     * @param flashLeverage Address of the flash leverage contract
     * @param pendleRouter Address of the Pendle router contract
     */
    constructor(
        address flashLeverage,
        address pendleRouter
    ) Ownable(msg.sender) {
        i_flashLeverage = IFlashLeverage(flashLeverage);
        i_pendleRouter = IPAllActionV3(pendleRouter);
    }

    /////////////////////////
    // External Functions

    /**
     * @notice Executes a leveraged position with optional token swapping
     * @dev If tokenIn != collateralToken, swaps tokens via Pendle before leveraging
     * @param params Parameters for the wrapper execution
     * @param leverageParams Parameters for the flash leverage operation
     */
    function leverage(
        LeverageWrapperParams memory params,
        LeverageParams memory leverageParams
    ) external validateAmount(params.amountTokenIn) {
        SwapParams memory swapParams = s_swapParams[
            leverageParams.collateralToken
        ];
        require(
            swapParams.pendleMarket != address(0),
            FlashLeverageWrapper__UnsupportedCollateralToken()
        );

        // Transfer input tokens from user to this contract
        // Note: _safeApprove doesn't work for some ERC20 tokens like USDC
        IERC20(params.tokenIn).transferFrom(
            msg.sender,
            address(this),
            params.amountTokenIn
        );

        // Swap to collateral token if needed
        if (params.tokenIn != leverageParams.collateralToken) {
            _swapToCollateralToken(
                params,
                swapParams,
                leverageParams.collateralToken
            );
        }

        // Approve flash leverage contract to spend collateral tokens
        _safeApprove(
            leverageParams.collateralToken,
            address(i_flashLeverage),
            type(uint256).max
        );

        // Execute the leveraged position
        i_flashLeverage.leverage(msg.sender, leverageParams);
    }

    /**
     * @notice Updates swap parameters for a specific collateral token
     * @dev Only owner can update swap parameters to ensure proper configuration
     * @param collateralToken The collateral token to configure
     * @param swapParams New swap parameters for the token
     */
    function updateSwapParams(
        address collateralToken,
        SwapParams memory swapParams
    ) external onlyOwner {
        s_swapParams[collateralToken] = swapParams;
    }

    /**
     * @notice Overrides renounceOwnership to prevent ownership renunciation
     * @dev Intentionally disabled to retain upgradeability and integration support management
     */
    function renounceOwnership() public override {}

    /////////////////////////
    // Internal Functions

    /**
     * @notice Swaps input tokens to collateral tokens via Pendle
     * @dev Uses stored swap parameters and handles excess token refunds
     * @param params Wrapper parameters containing swap details
     * @param collateralToken Target collateral token address
     */
    function _swapToCollateralToken(
        LeverageWrapperParams memory params,
        SwapParams memory swapParams,
        address collateralToken
    ) internal {
        // Approve Pendle router to spend input tokens
        _forceApprove(
            params.tokenIn,
            address(i_pendleRouter),
            params.amountTokenIn
        );

        // Execute swap from input token to PT (Principal Token)
        (uint256 amountCollateralOut, , ) = i_pendleRouter.swapExactTokenForPt(
            address(this),
            swapParams.pendleMarket,
            params.minCollateralOut,
            params.approxParams,
            TokenInput({
                tokenIn: params.tokenIn,
                netTokenIn: params.amountTokenIn,
                tokenMintSy: swapParams.underlyingToken,
                pendleSwap: params.pendleSwap,
                swapData: params.swapData
            }),
            params.limitOrderData
        );

        // Return any excess collateral tokens to user
        _transferBackRemaining(
            collateralToken,
            amountCollateralOut,
            params.minCollateralOut
        );
    }

    /**
     * @notice Transfers excess tokens back to the user
     * @dev Only transfers if actual output exceeds minimum required
     * @param token Token address to transfer
     * @param amountOut Actual amount received from swap
     * @param minAmount Minimum amount required for leverage
     */
    function _transferBackRemaining(
        address token,
        uint256 amountOut,
        uint256 minAmount
    ) internal {
        if (amountOut > minAmount) {
            uint256 amountRemaining;
            unchecked {
                amountRemaining = amountOut - minAmount;
            }
            _transferOut(token, msg.sender, amountRemaining);
        }
    }
}
