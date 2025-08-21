// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import {CollateralTokenConfig} from "../src/core/structs/CollateralTokenConfig.sol";
import {IMorpho, MarketParams, Id} from "@morpho/interfaces/IMorpho.sol";

contract WriteAddresses is Script {
    function _writeAddresses(
        address morphoAddress,
        CollateralTokenConfig[] memory tokensConfig,
        address USDC,
        address flashLeverageCoreAddress,
        address flashLeverageAddress,
        string memory path
    ) internal {
        IMorpho morpho = IMorpho(morphoAddress);
        string memory addresses = "addresses";

        vm.serializeAddress(
            addresses,
            "flashLeverageCoreAddress",
            flashLeverageCoreAddress
        );
        vm.serializeAddress(
            addresses,
            "flashLeverageAddress",
            flashLeverageAddress
        );

        // USDC
        string memory usdcToken = "USDC";
        IERC20Metadata usdc = IERC20Metadata(USDC);
        vm.serializeAddress(usdcToken, "address", address(usdc));
        vm.serializeString(usdcToken, "name", usdc.name());
        vm.serializeString(usdcToken, "symbol", usdc.symbol());
        vm.serializeUint(usdcToken, "valueInUsd", 1);
        usdcToken = vm.serializeUint(usdcToken, "decimals", usdc.decimals());
        vm.serializeString(addresses, "USDC", usdcToken);

        // Collateral Tokens

        string memory collateralTokens = "collateralTokens";
        for (uint256 i; i < tokensConfig.length; ++i) {
            string memory tokenObj = "tokenObj";

            IERC20Metadata token = IERC20Metadata(
                tokensConfig[i].collateralToken
            );
            MarketParams memory marketParams = morpho.idToMarketParams(
                Id.wrap(tokensConfig[i].morphoMarketId)
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
                tokensConfig[i].morphoMarketId
            );
            vm.serializeString(tokenObj, "loanToken", loanTokenObj);
            tokenObj = vm.serializeAddress(
                tokenObj,
                "pendleMarket",
                tokensConfig[i].pendleMarket
            );

            vm.serializeString(
                collateralTokens,
                vm.toString(address(token)),
                tokenObj
            );
            if (i == tokensConfig.length - 1) {
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
