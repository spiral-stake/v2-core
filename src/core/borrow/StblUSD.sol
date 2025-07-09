// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import {IStblUSD} from "../../interfaces/IStblUSD.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

library Error {
    error StblUSD__CallerNotAManagerAddress();
}

/**
 * @title StblUSD - SpiralStake Stable USD
 * @dev This is the ERC20 implementation of the StblUSD stablecoin which is
 *      1. Pegged to $1
 *      2. Overcollateralized exogenously (Staked stablecoins and their PTs)
 *      3. Minted and burned Algorithmically
 *      4. Borrow/Mint Rate - Comes through the dual lending mechanism of spiral stake protocol
 * @notice This contract is purely governed by the PositionManager contract
 */
contract StblUSD is IStblUSD, ERC20Permit, Ownable {
    string internal constant _NAME = "SpiralStake Stable USD";
    string internal constant _SYMBOL = "stblUSD";

    /////////////////////////
    // Manager Addresses

    address public positionManagerAddress;

    /////////////////////////
    // Events

    event PositionManagerAddressUpdated(address newPositionManagerAddress);

    constructor()
        Ownable(msg.sender)
        ERC20(_NAME, _SYMBOL)
        ERC20Permit(_NAME)
    {}

    /////////////////////
    // External Functions

    function setManagerAddresses(
        address _positionManagerAddress
    ) external override onlyOwner {
        positionManagerAddress = _positionManagerAddress;
        emit PositionManagerAddressUpdated(_positionManagerAddress);
    }

    function mint(address account, uint256 amount) external override {
        require(
            msg.sender == positionManagerAddress,
            Error.StblUSD__CallerNotAManagerAddress()
        );

        _mint(account, amount);
    }

    function burn(address account, uint256 amount) external override {
        require(
            msg.sender == positionManagerAddress,
            Error.StblUSD__CallerNotAManagerAddress()
        );

        _burn(account, amount);
    }
}
