// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import {TokenHelper} from "../libraries/TokenHelper.sol";
import {FLError} from "../libraries/Error.sol";

/// @title UserProxy
/// @notice Minimal proxy contract that holds user positions on Morpho
/// @dev This contract acts as an isolated wallet for each user's leverage positions.
///      It can only be controlled by the FlashLeverage contract and executes
///      calls to Morpho protocol on behalf of the user to maintain position isolation.
///      Uses clone pattern with initialize function for per-user configuration.
contract UserProxy is TokenHelper {
    /// @notice Address of the user who owns this proxy and can be initialized only once
    address public s_user;
    /// @notice Address of the FlashLeverage contract that controls this proxy
    address public immutable i_flashLeverage;
    /// @notice Address of the Morpho contract to borrow and repay
    address public immutable i_morpho;
    /// @notice Flag indicating whether manual mode is active for this proxy contract
    bool public s_manualMode;

    /////////////////////////
    // Events

    event ProxyInitialized(address indexed user);
    event ManualModeEnabled();

    /// @notice Sets the immutable flashLeverage address
    /// @param _flashLeverage Address of the FlashLeverage contract
    constructor(address _flashLeverage, address _morpho) {
        i_flashLeverage = _flashLeverage;
        i_morpho = _morpho;
    }

    /// @notice Initializes the clone with user address
    /// @param _user Address of the user who owns this proxy
    /// @dev Called once per clone in the same tx after deployment by the factory
    function initialize(address _user) external {
        require(
            msg.sender == i_flashLeverage,
            FLError.FlashLeverage__Unauthorised()
        );
        require(
            s_user == address(0),
            FLError.FlashLeverage__ProxyAlreadyInitialized()
        );
        s_user = _user;
        emit ProxyInitialized(_user);
    }

    /// @notice Executes arbitrary calls on behalf of this proxy contract
    /// @param data The encoded function call data to execute
    /// @return result The return data from the executed call
    /// @dev Can be called by either FlashLeverage (normal operation) or by the user
    ///      (only when manual mode is enabled). Used to interact with Morpho protocol
    ///      (supply, borrow, repay, withdraw) and token approvals.
    ///      Reverts if the target call fails for any reason.
    function execute(
        bytes calldata data
    ) external returns (bytes memory result) {
        if (msg.sender == i_flashLeverage) {
            require(!s_manualMode, FLError.FlashLeverage__ManualModeEnabled());
            // Proceed
        } else if (msg.sender == s_user) {
            require(s_manualMode, FLError.FlashLeverage__NotInManualMode());
            // Proceed
        } else {
            revert FLError.FlashLeverage__Unauthorised();
        }

        (bool success, bytes memory returnData) = i_morpho.call(data);
        require(success, FLError.FlashLeverage__ProxyCallFailed());
        return returnData;
    }

    /// @notice Enables manual mode allowing the user to call `execute`
    /// @dev Only FlashLeverage can trigger manual mode
    function enableManualMode() external {
        require(
            msg.sender == i_flashLeverage,
            FLError.FlashLeverage__Unauthorised()
        );
        s_manualMode = true;
        emit ManualModeEnabled();
    }

    /**
     * @notice Recovers ERC20 tokens accidentally sent to this contract or accumulated as rewards
     * @param token The address of the token to recover
     */
    function recover(address token) external {
        require(msg.sender == s_user, FLError.FlashLeverage__Unauthorised());
        _transferOut(token, s_user, _selfBalance(token));
    }
}
