// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

interface IOracleRouter {
    function getQuote(
        uint256 inAmount,
        address base,
        address quote
    ) external view returns (uint256);

    function getQuotes(
        uint256 inAmount,
        address base,
        address quote
    ) external view returns (uint256, uint256);
}
