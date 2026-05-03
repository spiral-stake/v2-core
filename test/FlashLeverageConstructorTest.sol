// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";

import {FlashLeverage} from "src/core/FlashLeverage/FlashLeverage.sol";
import {FLError} from "src/core/libraries/Error.sol";

contract FlashLeverageConstructorTest is Test {
    function test_constructor_revertsOnZeroOwnerAddress() external {
        vm.expectRevert(FLError.FlashLeverage__CannotBeZeroAddress.selector);
        new FlashLeverage(address(0), address(1), address(2));
    }
}
