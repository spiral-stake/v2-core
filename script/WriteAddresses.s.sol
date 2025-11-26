// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import {IMorpho, MarketParams, Id} from "@morpho/interfaces/IMorpho.sol";

contract WriteAddresses is Script {
    function _writeAddresses(
        address morphoAddress,
        address[] memory tokens,
        bytes32[] memory morphoMarketIds,
        address WETH,
        address flashLeverageAddress,
        string memory path
    ) internal {
        IMorpho morpho = IMorpho(morphoAddress);
        string memory addresses = "addresses";

        vm.serializeAddress(
            addresses,
            "flashLeverageAddress",
            flashLeverageAddress
        );

        // WETH
        string memory usdcToken = "WETH";
        IERC20Metadata weth = IERC20Metadata(WETH);
        vm.serializeAddress(usdcToken, "address", address(weth));
        vm.serializeString(usdcToken, "name", weth.name());
        vm.serializeString(usdcToken, "symbol", weth.symbol());
        vm.serializeUint(usdcToken, "valueInUsd", 1);
        usdcToken = vm.serializeUint(usdcToken, "decimals", weth.decimals());
        vm.serializeString(addresses, "WETH", usdcToken);

        // Collateral Tokens

        string memory collateralTokens = "collateralTokens";
        for (uint256 i; i < tokens.length; ++i) {
            string memory tokenObj = "tokenObj";

            IERC20Metadata token = IERC20Metadata(tokens[i]);
            MarketParams memory marketParams = morpho.idToMarketParams(
                Id.wrap(morphoMarketIds[i])
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
            vm.serializeBytes32(tokenObj, "morphoMarketId", morphoMarketIds[i]);
            tokenObj = vm.serializeString(tokenObj, "loanToken", loanTokenObj);

            vm.serializeString(
                collateralTokens,
                vm.toString(address(token)),
                tokenObj
            );
            if (i == tokens.length - 1) {
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
