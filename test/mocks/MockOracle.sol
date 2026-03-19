// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import {IOracle} from "@morpho/interfaces/IOracle.sol";

contract MockOracle is IOracle {
    uint256 private _price;

    constructor(uint256 initialPrice) {
        _price = initialPrice;
    }

    function price() external view override returns (uint256) {
        return _price;
    }

    function setPrice(uint256 newPrice) external {
        _price = newPrice;
    }
}
