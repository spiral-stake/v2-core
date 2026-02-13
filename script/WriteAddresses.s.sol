// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import {CollateralTokenConfig} from "../src/core/structs/CollateralTokenConfig.sol";
import {IMorpho, MarketParams, Id} from "@morpho/interfaces/IMorpho.sol";

import {console} from "forge-std/console.sol";

contract WriteAddresses is Script {
    function _writeAddresses(
        address morphoAddress,
        CollateralTokenConfig[] memory tokenConfigs,
        address flashLeverageAddress,
        address flashLeverageRouter,
        string memory path
    ) internal {
        IMorpho morpho = IMorpho(morphoAddress);
        string memory addresses = "addresses";

        vm.serializeAddress(addresses, "morphoAddress", morphoAddress);
        vm.serializeAddress(
            addresses,
            "flashLeverageAddress",
            flashLeverageAddress
        );
        vm.serializeAddress(
            addresses,
            "flashLeverageRouterAddress",
            flashLeverageRouter
        );

        // Collateral Tokens

        string memory collateralTokens = "collateralTokens";
        for (uint256 i; i < tokenConfigs.length; ++i) {
            string memory tokenObj = "tokenObj";

            IERC20Metadata token = IERC20Metadata(
                tokenConfigs[i].collateralToken
            );
            MarketParams memory marketParams = morpho.idToMarketParams(
                Id.wrap(tokenConfigs[i].morphoMarketId)
            );

            // Create loan token metadata object
            address loanTokenAddress = marketParams.loanToken;
            IERC20Metadata loanToken = IERC20Metadata(loanTokenAddress);
            string memory loanTokenObj = "loanTokenObj";
            vm.serializeAddress(loanTokenObj, "address", loanTokenAddress);
            vm.serializeString(loanTokenObj, "name", loanToken.name());
            vm.serializeString(loanTokenObj, "symbol", loanToken.symbol());

            loanTokenObj = vm.serializeUint(
                loanTokenObj,
                "decimals",
                loanToken.decimals()
            );

            vm.serializeAddress(tokenObj, "address", address(token));
            vm.serializeString(tokenObj, "name", token.name());
            vm.serializeString(tokenObj, "symbol", token.symbol());
            vm.serializeUint(tokenObj, "decimals", token.decimals());
            vm.serializeBytes32(
                tokenObj,
                "morphoMarketId",
                tokenConfigs[i].morphoMarketId
            );
            tokenObj = vm.serializeString(tokenObj, "loanToken", loanTokenObj);

            vm.serializeString(
                collateralTokens,
                vm.toString(address(token)),
                tokenObj
            );
            if (i == tokenConfigs.length - 1) {
                collateralTokens = vm.serializeString(
                    collateralTokens,
                    vm.toString(address(token)),
                    tokenObj
                );
            }
        }

        addresses = vm.serializeString(
            addresses,
            "collateralTokens",
            collateralTokens
        );

        vm.writeJson(
            addresses,
            string.concat(path, vm.toString(block.chainid), ".json")
        );
    }
}
