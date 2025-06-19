// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";

contract WriteAddressesToJson is Script {
    function _writeAddressesToJson(
        address spiUsdAddress,
        address positionManagerAddress,
        address[] memory collateralTokens,
        address frxUSD
    ) external {
        string memory obj = "obj";

        vm.serializeAddress(
            obj,
            "positionManagerAddress",
            positionManagerAddress
        );

        vm.serializeAddress(obj, "frxUSD", frxUSD);

        // SPIUSD
        string memory spiUsdObj = "spiUsdObj";
        IERC20Metadata spiUsd = IERC20Metadata(spiUsdAddress);

        vm.serializeAddress(spiUsdObj, "address", address(spiUsd));
        vm.serializeString(spiUsdObj, "name", spiUsd.name());
        vm.serializeString(spiUsdObj, "symbol", spiUsd.symbol());
        spiUsdObj = vm.serializeString(
            spiUsdObj,
            "decimals",
            vm.toString(spiUsd.decimals())
        );
        vm.serializeString(obj, "SPIUSD", spiUsdObj);

        // Collateral Tokens
        vm.serializeString(obj, "collateralTokens", spiUsdObj);

        string memory collateralTokensObj = "collateralTokensObj";
        for (uint256 i; i < collateralTokens.length; ++i) {
            string memory tokenObj = "tokenObj";

            IERC20Metadata token = IERC20Metadata(collateralTokens[i]);
            vm.serializeAddress(tokenObj, "address", address(token));
            vm.serializeString(tokenObj, "name", token.name());
            vm.serializeString(tokenObj, "symbol", token.symbol());
            tokenObj = vm.serializeString(
                tokenObj,
                "decimals",
                vm.toString(token.decimals())
            );

            vm.serializeString(
                collateralTokensObj,
                vm.toString(address(token)),
                tokenObj
            );
            if (i == collateralTokens.length - 1) {
                collateralTokensObj = vm.serializeString(
                    collateralTokensObj,
                    vm.toString(address(token)),
                    tokenObj
                );
            }
        }

        obj = vm.serializeString(obj, "collateralTokens", collateralTokensObj);

        vm.writeJson(
            obj,
            string.concat("./addresses/", vm.toString(block.chainid), ".json")
        );

        vm.writeJson(
            obj,
            string.concat(
                "../client-v1/src/addresses/",
                vm.toString(block.chainid),
                ".json"
            )
        );

        vm.writeJson(
            obj,
            string.concat(
                "../temp-server-v1/addresses/",
                vm.toString(block.chainid),
                ".json"
            )
        );
    }
}
