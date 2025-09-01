// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

/// @title UserProxy
/// @notice Minimal proxy contract that holds user positions on Morpho
/// @dev This contract acts as an isolated wallet for each user's leverage positions.
///      It can only be controlled by the FlashLeverageCore contract and executes
///      calls to Morpho protocol on behalf of the user to maintain position isolation.
contract UserProxy {
    /// @notice Address of the FlashLeverageCore contract that controls this proxy
    address public immutable leverageCore;

    /// @notice Initializes the proxy contract with leverage core and user addresses
    /// @param _leverageCore Address of the FlashLeverageCore contract
    constructor(address _leverageCore) {
        leverageCore = _leverageCore;
    }

    /// @notice Ensures only the FlashLeverageCore contract can call protected functions
    modifier onlyLeverageCore() {
        require(msg.sender == leverageCore, "UserProxy: only leverage core");
        _;
    }

    /// @notice Executes arbitrary calls on behalf of this proxy contract
    /// @param target The contract address to call
    /// @param data The encoded function call data to execute
    /// @return result The return data from the executed call
    /// @dev Only the FlashLeverageCore can call this function. Used to interact with
    ///      Morpho protocol (supply, borrow, repay, withdraw) and token approvals.
    ///      Reverts if the target call fails for any reason.
    function execute(
        address target,
        bytes calldata data
    ) external onlyLeverageCore returns (bytes memory result) {
        (bool success, bytes memory returnData) = target.call(data);
        require(success, "UserProxy: call failed");
        return returnData;
    }
}
