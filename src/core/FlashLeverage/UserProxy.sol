// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

/// @title UserProxy
/// @notice Minimal proxy contract that holds user positions on Morpho
/// @dev This contract acts as an isolated wallet for each user's leverage positions.
///      It can only be controlled by the FlashLeverageCore contract and executes
///      calls to Morpho protocol on behalf of the user to maintain position isolation.
///      Uses clone pattern with initialize function for per-user configuration.
contract UserProxy {
    /// @notice Address of the user who owns this proxy and can be initialized only once
    address public user;
    /// @notice Address of the FlashLeverageCore contract that controls this proxy
    address public immutable leverageCore;
    /// @notice Address of the Morpho contract to borrow and repay
    address public immutable morpho;

    /// @notice Sets the immutable leverageCore address
    /// @param _leverageCore Address of the FlashLeverageCore contract
    constructor(address _leverageCore, address _morpho) {
        leverageCore = _leverageCore;
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
    /// @dev Can be called by either FlashLeverageCore (normal operation) or by the user
    ///      (only when recovery mode is enabled). Used to interact with Morpho protocol
    ///      (supply, borrow, repay, withdraw) and token approvals.
    ///      Reverts if the target call fails for any reason.
    function execute(
        bytes calldata data
    ) external returns (bytes memory result) {
        if (msg.sender == leverageCore) {
            // Execute
        } else if (msg.sender == user) {
            (, bytes memory recoveryModeData) = leverageCore.call(
                abi.encodeWithSignature("recoveryMode()")
            );
            bool recoveryMode = abi.decode(recoveryModeData, (bool));
            require(recoveryMode, "UserProxy: Not in Recovery Mode");
            // Execute
        } else {
            revert("UserProxy: Unauthorised");
        }

        (bool success, bytes memory returnData) = morpho.call(data);
        require(success, "UserProxy: Call Failed");
        return returnData;
    }
}
