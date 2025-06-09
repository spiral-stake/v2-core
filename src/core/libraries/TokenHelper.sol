// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

abstract contract TokenHelper {
    using SafeERC20 for IERC20;

    address internal constant NATIVE = address(0);

    function _transferIn(address token, address from, uint256 amount) internal {
        if (token == NATIVE) {
            require(msg.value >= amount, "insufficient eth");

            uint256 excess = msg.value - amount;
            if (excess > 0) {
                (bool success, ) = from.call{value: excess}("");
                require(success, "excess eth return failed");
            }
        } else if (amount != 0)
            IERC20(token).safeTransferFrom(from, address(this), amount);
    }

    function _transferOut(address token, address to, uint256 amount) internal {
        if (amount == 0) return;
        if (token == NATIVE) {
            (bool success, ) = to.call{value: amount}("");
            require(success, "eth send failed");
        } else {
            IERC20(token).safeTransfer(to, amount);
        }
    }
}
