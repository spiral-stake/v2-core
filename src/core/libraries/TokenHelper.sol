// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

abstract contract TokenHelper {
    using SafeERC20 for IERC20;

    address internal constant NATIVE = address(0);

    function _transferIn(address token, address from, uint256 amount) internal {
        if (amount == 0) return;
        IERC20(token).safeTransferFrom(from, address(this), amount);
    }

    function _selfBalance(address token) internal view returns (uint256) {
        return
            (token == NATIVE)
                ? address(this).balance
                : IERC20(token).balanceOf(address(this));
    }

    function _selfBalance(IERC20 token) internal view returns (uint256) {
        return token.balanceOf(address(this));
    }

    function _transferOut(address token, address to, uint256 amount) internal {
        if (amount == 0) return;
        IERC20(token).safeTransfer(to, amount);
    }

    function _forceApprove(
        address token,
        address spender,
        uint256 value
    ) internal {
        IERC20(token).forceApprove(spender, value);
    }
}
