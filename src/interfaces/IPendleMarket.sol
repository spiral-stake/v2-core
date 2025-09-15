// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

interface IPendleMarket {
    function readTokens()
        external
        view
        returns (address _SY, address _PT, address _YT);

    function isExpired() external view returns (bool);
}
