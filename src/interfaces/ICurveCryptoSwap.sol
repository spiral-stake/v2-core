// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

interface ICurveCryptoSwap {
    function exchange(
        uint256 i,
        uint256 j,
        uint256 in_amount,
        uint256 min_amount,
        address receiver
    ) external payable returns (uint256);

    function get_dy(
        uint256 i,
        uint256 j,
        uint256 dx
    ) external view returns (uint256);
}
