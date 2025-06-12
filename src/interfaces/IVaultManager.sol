// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

interface IVaultManager {
    function depositCollateralAndMintSPIUSD(
        address collateralToken,
        uint256 amountCollateral,
        uint256 amountToMint
    ) external;

    function depositCollateral(
        address collateralToken,
        uint256 amountCollateral
    ) external;

    function mintSPIUSD(address collateralToken, uint256 amountToMint) external;

    function redeemCollateralAndBurnSPIUSD(
        address collateralToken,
        uint256 amountCollateral,
        uint256 amountToBurn
    ) external;

    function redeemCollateral(
        address collateralToken,
        uint256 amountCollateral
    ) external;

    function burnSPIUSD(address collateralToken, uint256 amountToBurn) external;

    function liquidate(address user, address collateralToken) external;

    function getUserVaultLTV(
        address user,
        address collateralToken
    ) external returns (uint256);
}
