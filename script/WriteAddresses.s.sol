// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import {IMorpho, MarketParams, Id} from "@morpho/interfaces/IMorpho.sol";
import {FlashLeverage} from "./DeployFlashLeverage.s.sol";
import {MarketConfig} from "../src/core/structs/MarketConfig.sol";

interface IPT {
    function expiry() external view returns (uint256);
}

contract WriteAddresses is Script {
    function _writeAddresses(
        address morphoAddress,
        MarketConfig[] memory marketConfigs,
        address flashLeverageAddress,
        address flashLeverageRouter,
        string memory path
    ) internal {
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
        string memory markets = "markets";

        uint256 marketsLength = marketConfigs.length;
        for (uint256 i; i < marketsLength; ++i) {
            string memory marketObj = "marketObj";

            bytes32 marketId = marketConfigs[i].marketId;

            MarketParams memory market = IMorpho(morphoAddress)
                .idToMarketParams(Id.wrap(marketId));

            IERC20Metadata token = IERC20Metadata(market.collateralToken);

            // Create collateral token metadata object
            string memory tokenObj = "tokenObj";
            vm.serializeAddress(tokenObj, "address", address(token));
            vm.serializeString(tokenObj, "name", token.name());
            string memory symbol = token.symbol();
            vm.serializeString(tokenObj, "symbol", symbol);
            if (_startsWith(symbol, "PT-")) {
                vm.serializeUint(
                    tokenObj,
                    "maturity",
                    IPT(address(token)).expiry()
                );
            }
            tokenObj = vm.serializeUint(tokenObj, "decimals", token.decimals());

            // Create loan token metadata object
            address loanTokenAddress = market.loanToken;
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

            vm.serializeBool(
                marketObj,
                "correlated",
                marketConfigs[i].isCorrelated
            );
            vm.serializeAddress(marketObj, "irm", market.irm);
            vm.serializeAddress(marketObj, "oracle", market.oracle);
            vm.serializeUint(marketObj, "liqLtv", market.lltv);

            vm.serializeUint(
                marketObj,
                "maxLtv",
                FlashLeverage(flashLeverageAddress).getMaxLtv(market)
            );

            vm.serializeBytes32(marketObj, "morphoMarketId", marketId);

            vm.serializeString(marketObj, "collateralToken", tokenObj);

            marketObj = vm.serializeString(
                marketObj,
                "loanToken",
                loanTokenObj
            );

            vm.serializeString(markets, vm.toString(marketId), marketObj);
            if (i == marketsLength - 1) {
                markets = vm.serializeString(
                    markets,
                    vm.toString(marketId),
                    marketObj
                );
            }
        }

        addresses = vm.serializeString(addresses, "markets", markets);

        vm.writeJson(
            addresses,
            string.concat(path, vm.toString(block.chainid), ".json")
        );
    }

    function _startsWith(
        string memory str,
        string memory prefix
    ) internal pure returns (bool) {
        bytes memory strBytes = bytes(str);
        bytes memory prefixBytes = bytes(prefix);
        if (prefixBytes.length > strBytes.length) return false;
        for (uint256 i; i < prefixBytes.length; ++i) {
            if (strBytes[i] != prefixBytes[i]) return false;
        }
        return true;
    }
}
