// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

/**
 * @title CollateralTokenConfig
 * @dev Configuration contract for collateral token settings
 * @notice Contains all collateral token configurations for the Flash Leverage system
 */
contract CollateralTokenConfig {
    /**
     * @dev Returns all collateral token configurations
     * @return collateralTokens Array of supported collateral tokens
     * @return morphoMarketIds Array of morphoMarketIds of the collateralTokens
     */
    function getTokenConfigs()
        external
        pure
        returns (
            address[] memory collateralTokens,
            bytes32[] memory morphoMarketIds
        )
    {
        collateralTokens = new address[](2);
        morphoMarketIds = new bytes32[](2);
    }

    function getTokenWhales()
        external
        pure
        returns (address[] memory tokenWhales)
    {
        tokenWhales = new address[](1);
    }
}
