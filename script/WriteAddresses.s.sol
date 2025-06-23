// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";

contract WriteAddressesToJson is Script {
    function _writeAddressesToJson(
        address stblUSDAddress,
        address positionManagerAddress,
        address flashLeverageAddress,
        address[] memory collateralTokens,
        address frxUSD
    ) external {
        string memory obj = "obj";

        vm.serializeAddress(
            obj,
            "positionManagerAddress",
            positionManagerAddress
        );
        vm.serializeAddress(obj, "flashLeverageAddress", flashLeverageAddress);

        vm.serializeAddress(obj, "frxUSD", frxUSD);

        // StblUSD
        string memory stblUSDObj = "stblUSDObj";
        IERC20Metadata stblUSD = IERC20Metadata(stblUSDAddress);

        vm.serializeAddress(stblUSDObj, "address", address(stblUSD));
        vm.serializeString(stblUSDObj, "name", stblUSD.name());
        vm.serializeString(stblUSDObj, "symbol", stblUSD.symbol());
        stblUSDObj = vm.serializeString(
            stblUSDObj,
            "decimals",
            vm.toString(stblUSD.decimals())
        );
        vm.serializeString(obj, "StblUSD", stblUSDObj);

        // Collateral Tokens
        vm.serializeString(obj, "collateralTokens", stblUSDObj);

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
