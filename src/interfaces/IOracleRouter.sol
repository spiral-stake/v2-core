// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

interface IOracleRouter {
    // Events
    event ConfigSet(
        address indexed asset0,
        address indexed asset1,
        address indexed oracle
    );
    event FallbackOracleSet(address indexed fallbackOracle);
    event ResolvedVaultSet(address indexed vault, address indexed asset);

    // Views
    function name() external view returns (string memory);

    function fallbackOracle() external view returns (address);

    function resolvedVaults(
        address vault
    ) external view returns (address asset);

    function getConfiguredOracle(
        address base,
        address quote
    ) external view returns (address);

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

    function resolveOracle(
        uint256 inAmount,
        address base,
        address quote
    )
        external
        view
        returns (
            uint256 resolvedAmount,
            address baseResolved,
            address quoteResolved,
            address oracle
        );

    // Governance-only setters
    function govSetConfig(address base, address quote, address oracle) external;

    function govSetResolvedVault(address vault, bool set) external;

    function govSetFallbackOracle(address _fallbackOracle) external;
}
