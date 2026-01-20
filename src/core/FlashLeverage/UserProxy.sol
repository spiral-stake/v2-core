// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import {TokenHelper} from "../libraries/TokenHelper.sol";

/// @title UserProxy
/// @notice Minimal proxy contract that holds user positions on Morpho
/// @dev This contract acts as an isolated wallet for each user's leverage positions.
///      It can only be controlled by the FlashLeverage contract and executes
///      calls to Morpho protocol on behalf of the user to maintain position isolation.
///      Uses clone pattern with initialize function for per-user configuration.
contract UserProxy is TokenHelper {
    /// @notice Address of the user who owns this proxy and can be initialized only once
    address public user;
    /// @notice Address of the FlashLeverage contract that controls this proxy
    address public immutable flashLeverage;
    /// @notice Address of the Morpho contract to borrow and repay
    address public immutable morpho;
    /// @notice Flag indicating whether recovery mode is active for this proxy contract
    bool public recoveryMode;

    /// @notice Sets the immutable flashLeverage address
    /// @param _flashLeverage Address of the FlashLeverage contract
    constructor(address _flashLeverage, address _morpho) {
        flashLeverage = _flashLeverage;
        morpho = _morpho;
    }

    /// @notice Initializes the clone with user address
    /// @param _user Address of the user who owns this proxy
    /// @dev Called once per clone in the same tx after deployment by the factory
    function initialize(address _user) external {
        require(user == address(0), "UserProxy: Already Initialized");
        user = _user;
    }

    /// @notice Executes arbitrary calls on behalf of this proxy contract
    /// @param data The encoded function call data to execute
    /// @return result The return data from the executed call
    /// @dev Can be called by either FlashLeverage (normal operation) or by the user
    ///      (only when recovery mode is enabled). Used to interact with Morpho protocol
    ///      (supply, borrow, repay, withdraw) and token approvals.
    ///      Reverts if the target call fails for any reason.
    function execute(
        bytes calldata data
    ) external returns (bytes memory result) {
        if (msg.sender == flashLeverage) {
            // Proceed
        } else if (msg.sender == user) {
            require(recoveryMode, "UserProxy: Not in Recovery Mode");
            // Proceed
        } else {
            revert("UserProxy: Unauthorised");
        }

        (bool success, bytes memory returnData) = morpho.call(data);
        require(success, "UserProxy: Call Failed");
        return returnData;
    }

    /// @notice Enables recovery mode allowing the user to call `execute`
    /// @dev Only FlashLeverage can trigger recovery mode
    function enableRecoveryMode() external {
        require(msg.sender == flashLeverage, "UserProxy: Unauthorised");
        recoveryMode = true;
    }

    /**
     * @notice Recovers ERC20 tokens accidentally sent to this contract or accumulated as rewards
     * @param token The address of the token to recover
     */
    function recover(address token) external {
        require(msg.sender == user, "UserProxy: Unauthorised");
        _transferOut(token, user, _selfBalance(token));
    }
}
