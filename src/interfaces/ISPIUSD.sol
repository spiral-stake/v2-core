// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

interface ISPIUSD {
    function setManagerAddresses(address _vaultManagerAddress) external;

    function mint(address _account, uint256 _amount) external;

    function burn(address _account, uint256 _amount) external;
}
