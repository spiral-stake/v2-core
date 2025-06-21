// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import {ISPIUSD, IERC20} from "../../interfaces/ISPIUSD.sol";
import {IERC3156FlashBorrower} from "@openzeppelin/contracts/interfaces/IERC3156FlashBorrower.sol";
import {IPositionManager} from "../../interfaces/IPositionManager.sol";
import {Errors} from "../libraries/Errors.sol";
import {Math} from "../libraries/Math.sol";
import {TokenHelper} from "../libraries/TokenHelper.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ICurveCryptoSwap} from "../../interfaces/ICurveCryptoSwap.sol";
import {Position} from "../structs/Position.sol"; // Debt Positions from PositionManager
import {LeveragePosition} from "../structs/LeveragePosition.sol";

import {console} from "forge-std/console.sol";

/**
 * @title FlashLeverage
 * @notice This contract allows users to leverage their yield-bearing assets using SPIUSD-based flash loans.
 *         It opens a larger position in a single atomic transaction using the ERC-3156 flash loan standard.
 */
contract FlashLeverage is IERC3156FlashBorrower, TokenHelper, Ownable2Step {
    using Math for uint256;

    enum Action {
        LEVERAGE,
        UNLEVERAGE
    }

    /////////////////////////
    // Constants and Immutables

    /// @notice SPIUSD stablecoin contract used for CDP-based leveraging
    ISPIUSD private immutable SPIUSD;

    /// @notice PositionManager contract that handles debt positions for SPIUSD
    IPositionManager private immutable i_positionManager; // Is also the lender of SPIUSD flash loan

    // 80% max LTV gives upto 5x leverage, for optimal returns
    uint256 public constant MAX_LEVERAGE_LTV = 800e15;

    /////////////////////////
    // Storage

    mapping(address collateralToken => address curvePool) private s_curvePools;

    address private s_treasury;

    mapping(address user => LeveragePosition[]) private s_userLeveragePositions;

    /////////////////////////
    // Modifiers

    modifier isSupportedCollateralToken(address token) {
        require(
            s_curvePools[token] != address(0),
            Errors.PositionManager__UnsupportedCollateralToken()
        );
        _;
    }

    constructor(
        address positionManagerAddress,
        address treasury
    ) Ownable(msg.sender) {
        i_positionManager = IPositionManager(positionManagerAddress);
        SPIUSD = ISPIUSD(i_positionManager.getSPIUSD());
        s_treasury = treasury;
    }

    /**
     * @notice Callback function called by the SPIUSD lender during a flash loan
     * @dev Decodes leverage intent, swaps SPIUSD to collateral, opens a leveraged position, and repays loan.
     * @param initiator Must be this contract
     * @param token Token being borrowed (must be SPIUSD)
     * @param amountLoan Amount of SPIUSD borrowed
     * @param fee Flash loan fee
     * @param data ABI-encoded parameters: (collateralToken, userCollateralAmount)
     * @return bytes32 Confirmation of successful flash loan callback
     */
    function onFlashLoan(
        address initiator,
        address token,
        uint256 amountLoan,
        uint256 fee,
        bytes calldata data
    ) external override returns (bytes32) {
        require(
            msg.sender == address(i_positionManager),
            Errors.FlashLeverage__UntrustedLender()
        );
        require(
            initiator == address(this),
            Errors.FlashLeverage__UntrustedLoanInitiator()
        );
        require(
            token == address(SPIUSD),
            Errors.FlashLeverage__InvalidLoanToken()
        );

        Action action = abi.decode(data, (Action));

        if (action == Action.LEVERAGE) {
            _handleLeverage(amountLoan, fee, data);
        } else {
            _handleUnleverage(amountLoan, fee, data);
        }

        return keccak256("ERC3156FlashBorrower.onFlashLoan");
    }

    function _handleLeverage(
        uint256 amountLoan,
        uint256 fee,
        bytes calldata data
    ) internal {
        (
            ,
            address user,
            address collateralToken,
            uint256 userCollateralAmount
        ) = abi.decode(data, (Action, address, address, uint256));

        ICurveCryptoSwap curvePool = ICurveCryptoSwap(
            s_curvePools[collateralToken]
        );

        SPIUSD.approve(address(curvePool), amountLoan);
        uint256 flashSwappedCollateral = curvePool.exchange(
            1,
            0,
            amountLoan,
            0,
            address(this)
        );

        uint256 totalCollateral = userCollateralAmount + flashSwappedCollateral;

        IERC20(collateralToken).approve(
            address(i_positionManager),
            totalCollateral
        );
        uint256 positionId = i_positionManager.openPosition(
            collateralToken,
            totalCollateral,
            amountLoan + fee
        );

        SPIUSD.transfer(address(i_positionManager), amountLoan + fee);

        s_userLeveragePositions[user].push(
            LeveragePosition({
                debtPositionId: positionId,
                userCollateralDeposited: userCollateralAmount
            })
        );
    }

    function _handleUnleverage(
        uint256 amountLoan,
        uint256 fee,
        bytes calldata data
    ) internal {
        (
            ,
            address user,
            uint256 debtPositionId,
            address collateralToken,
            uint256 totalCollateralDeposited
        ) = abi.decode(data, (Action, address, uint256, address, uint256));

        i_positionManager.redeemCollateralAndBurnSPIUSD(
            debtPositionId,
            totalCollateralDeposited,
            amountLoan
        );

        ICurveCryptoSwap curvePool = ICurveCryptoSwap(
            s_curvePools[collateralToken]
        );

        IERC20(collateralToken).approve(
            address(curvePool),
            totalCollateralDeposited
        );
        uint256 spiUsdReceived = curvePool.exchange(
            0,
            1,
            totalCollateralDeposited,
            0,
            address(this)
        );

        require(
            spiUsdReceived >= amountLoan + fee,
            Errors.FlashLeverage__InsufficientCollateralToUnleverage()
        );

        SPIUSD.transfer(address(i_positionManager), amountLoan + fee);

        if (spiUsdReceived > amountLoan + fee) {
            uint256 amountRemainingSpiUsd = spiUsdReceived - (amountLoan + fee);
            SPIUSD.approve(address(curvePool), amountRemainingSpiUsd);
            curvePool.exchange(1, 0, amountRemainingSpiUsd, 0, user);
        }
    }

    /**
     * @notice Public function to initiate a flash loan and create leverage position
     * @param collateralToken Address of the token to leverage
     * @param userCollateralAmount Amount of collateral provided by the user
     * @param desiredLtv Desired Loan-To-Value ratio (in 1e18 precision)
     */
    function leverage(
        address collateralToken,
        uint256 userCollateralAmount,
        uint256 desiredLtv
    ) external isSupportedCollateralToken(collateralToken) {
        require(
            desiredLtv <= MAX_LEVERAGE_LTV,
            Errors.FlashLeverage__ExceedsMaxLeverageLTV()
        );

        _transferIn(collateralToken, msg.sender, userCollateralAmount);

        uint256 calculatedLoanAmount = _calculateLoanAmount(
            collateralToken,
            userCollateralAmount,
            desiredLtv
        );

        _revertIfExceedsMaxLtv(
            collateralToken,
            calculatedLoanAmount,
            userCollateralAmount
        );

        bytes memory data = abi.encode(
            Action.LEVERAGE,
            msg.sender,
            collateralToken,
            userCollateralAmount
        );

        i_positionManager.flashLoan(
            this,
            address(SPIUSD),
            calculatedLoanAmount,
            data
        );
    }

    function unleverage(uint256 leveragePositionId) external {
        Position memory associatedDebtPosition = i_positionManager.getPosition(
            s_userLeveragePositions[msg.sender][leveragePositionId]
                .debtPositionId
        );

        bytes memory data = abi.encode(
            Action.UNLEVERAGE,
            msg.sender,
            leveragePositionId,
            associatedDebtPosition.collateralToken,
            associatedDebtPosition.collateralDeposited
        );

        delete s_userLeveragePositions[msg.sender][leveragePositionId];

        i_positionManager.flashLoan(
            this,
            address(SPIUSD),
            associatedDebtPosition.SPIUSDMinted,
            data
        );
    }

    /**
     * @notice Add or remove supported collateral tokens and their Curve pools
     * @param collateralTokens List of collateral token addresses
     * @param curvePools List of Curve pool addresses; use address(0) to remove support
     */
    function addSupportedCollateralTokens(
        address[] memory collateralTokens,
        address[] memory curvePools
    ) external onlyOwner {
        require(
            collateralTokens.length == curvePools.length,
            "Length Mismatch"
        );

        for (uint256 i = 0; i < collateralTokens.length; i++) {
            require(
                collateralTokens[i] != address(0),
                Errors.PositionManager__InvalidTokenAddress()
            );
            s_curvePools[collateralTokens[i]] = curvePools[i];
        }
    }

    /**
     * @notice Disabled renounceOwnership for upgradeability and admin control
     */
    function renounceOwnership() public override {}

    /**
     * @dev Internal function to calculate flash loan amount based on user's collateral and Ltv
     * @param collateralToken The token being used as collateral
     * @param userCollateralAmount Amount of collateral supplied by user
     * @param ltv Desired Loan-To-Value ratio (1e18 precision)
     * @return amountToBorrow SPIUSD amount to borrow
     */
    function _calculateLoanAmount(
        address collateralToken,
        uint256 userCollateralAmount,
        uint256 ltv
    ) private view returns (uint256) {
        uint256 userCollateralInUsd = i_positionManager.getTokenUsdValue(
            collateralToken,
            userCollateralAmount
        );

        return
            (Math.ONE.mulDown(userCollateralInUsd).divDown(Math.ONE - ltv)) -
            userCollateralInUsd;
    }

    /**
     * @dev Internal check to ensure Ltv doesn't exceed protocol max limit
     * @param collateralToken Token used as collateral
     * @param flashLoanAmount SPIUSD amount borrowed via flash loan
     * @param userCollateralAmount User-supplied collateral amount
     */
    function _revertIfExceedsMaxLtv(
        address collateralToken,
        uint256 flashLoanAmount,
        uint256 userCollateralAmount
    ) private view {
        uint256 flashConvertedCollateral = ICurveCryptoSwap(
            s_curvePools[collateralToken]
        ).get_dy(1, 0, flashLoanAmount); // 1: SPIUSD, 0: Collateral

        uint256 totalCollateralValueInUsd = i_positionManager.getTokenUsdValue(
            collateralToken,
            flashConvertedCollateral + userCollateralAmount
        );

        uint256 effectiveLtv = flashLoanAmount.divDown(
            totalCollateralValueInUsd
        );

        require(
            effectiveLtv <= i_positionManager.MAX_LTV(),
            Errors.FlashLeverage__ExceedsMaxLTV()
        );
    }

    /////////////////////////
    // Constants and Immutables

    function getUserLeveragePositions(
        address user
    ) external view returns (LeveragePosition[] memory) {
        return s_userLeveragePositions[user];
    }
}
