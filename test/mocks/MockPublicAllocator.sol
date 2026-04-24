// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import {Withdrawal, MarketParams} from "@morpho-public-allocator/interfaces/IPublicAllocator.sol";

contract MockPublicAllocator {
    function reallocateTo(
        address,
        Withdrawal[] calldata,
        MarketParams calldata
    ) external payable {}
}
