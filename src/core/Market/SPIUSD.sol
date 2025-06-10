// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import {ISPIUSD} from "../../interfaces/ISPIUSD.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Errors} from "../libraries/Errors.sol";

/**
 * @title SPIUSD - Spiral Stake USD
 * @dev This is the ERC20 implementation of the SPIUSD stablecoin which is
 *      1. Pegged to $1
 *      2. Overcollateralized exogenously (Staked stablecoins and their PTs)
 *      3. Minted and burned Algorithmically
 *      4. Borrow/Mint Rate - Comes through the dual lending mechanism of spiral stake protocol
 * @notice This contract is purely governed by the VaultManager contract
 */
contract SPIUSD is ISPIUSD, ERC20Permit, Ownable {
    string internal constant _NAME = "Spiral Stake USD";
    string internal constant _SYMBOL = "SPIUSD";

    /////////////////////////
    // Manager Addresses

    address public vaultManagerAddress;

    /////////////////////////
    // Events

    event VaultManagerAddressUpdated(address newVaultManagerAddress);

    constructor(
        address _owner
    ) Ownable(_owner) ERC20(_NAME, _SYMBOL) ERC20Permit(_NAME) {}

    /////////////////////////
    // External Functions

    function setManagerAddresses(
        address _vaultManagerAddress
    ) external override onlyOwner {
        vaultManagerAddress = _vaultManagerAddress;
        emit VaultManagerAddressUpdated(_vaultManagerAddress);
    }

    function mint(address _account, uint256 _amount) external override {
        require(
            msg.sender == vaultManagerAddress,
            Errors.SPIUSD__CallerNotAManagerAddress()
        );

        _mint(_account, _amount);
    }

    function burn(address _account, uint256 _amount) external override {
        require(
            msg.sender == vaultManagerAddress,
            Errors.SPIUSD__CallerNotAManagerAddress()
        );

        _burn(_account, _amount);
    }
}
