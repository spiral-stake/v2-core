// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

interface ICurveStableSwap {
    function exchange(
        int256 i,
        int256 j,
        uint256 in_amount,
        uint256 min_amount,
        address receiver
    ) external payable returns (uint256);

    function get_dy(
        int256 i,
        int256 j,
        uint256 dx
    ) external view returns (uint256);
}
