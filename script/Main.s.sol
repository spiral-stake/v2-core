// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";
import {HelperConfig, ChainConfig} from "./HelperConfig.s.sol";
import {DeploySPIUSD} from "./DeploySPIUSD.s.sol";
import {DeployPositionManager} from "./DeployPositionManager.s.sol";
import {WriteAddressesToJson} from "./WriteAddresses.s.sol";
import {DeployFlashLeverage} from "./DeployFlashLeverage.s.sol";

interface IERC20Mock {
    function mint(address account, uint256 amount) external;
}

contract Main is Script {
    address payable private user =
        payable(0x08675879B01177a9Bc80A7FC58c032cFA2Bb7742);
    uint256 private constant AMOUNT_COLLATERAL_TOKEN = 100000000e18;
    uint256 private constant AMOUNT_NATIVE = 100e18;

    function run() external {
        HelperConfig helperConfig = new HelperConfig();
        ChainConfig memory chain = helperConfig.deployIfNeededAndGetConfig();

        if (chain.isLocal) {
            address spiUsdAddress = (new DeploySPIUSD()).run();

            address positionManagerAddress = (new DeployPositionManager()).run(
                spiUsdAddress,
                chain.collateralTokens,
                chain.priceFeeds,
                chain.treasury
            );

            address flashLeverageAddress = (
                new DeployFlashLeverage().run(
                    positionManagerAddress,
                    new address[](0),
                    new address[](0),
                    chain.treasury
                )
            );

            (new WriteAddressesToJson())._writeAddressesToJson(
                spiUsdAddress,
                positionManagerAddress,
                flashLeverageAddress,
                chain.collateralTokens,
                chain.frxUSD
            );

            _mintCollateralTokens(
                user,
                chain.collateralTokens,
                AMOUNT_COLLATERAL_TOKEN
            );

            _mintNative(user, AMOUNT_NATIVE);
        }
    }

    function _mintCollateralTokens(
        address _user,
        address[] memory collateralTokens,
        uint256 amountToken
    ) private {
        for (uint256 j = 0; j < collateralTokens.length; j++) {
            address collateralToken = collateralTokens[j];

            vm.startBroadcast();

            IERC20Mock(collateralToken).mint(_user, amountToken);

            vm.stopBroadcast();
        }
    }

    function _mintNative(address payable _user, uint256 amountNative) private {
        vm.startBroadcast();
        _user.transfer(amountNative);
        vm.stopBroadcast();
    }
}
