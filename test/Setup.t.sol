// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {CollateralTokenConfig} from "../src/core/structs/CollateralTokenConfig.sol";
import {FlashLeverage} from "../src/core/leverage/FlashLeverage.sol";
import {IFlashLeverageCore} from "../src/interfaces/IFlashLeverageCore.sol";
import {IMorpho, MarketParams, Id} from "@morpho/interfaces/IMorpho.sol";
import {Main} from "../script/Main.s.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";

contract Setup is Test {
    IFlashLeverageCore flc;
    FlashLeverage fl;
    IMorpho morpho;
    address pendleRouter;
    CollateralTokenConfig[] tokensConfig;
    uint256 liquidationBuffer;
    uint256 slippageBuffer;
    address treasury;
    address USDC;

    function setUp() external virtual {
        // Create fork
        uint256 mainnetFork = vm.createFork(
            "https://mainnet.infura.io/v3/34c180ccaea34433a2a35cb904afb19b"
        );
        vm.selectFork(mainnetFork);
        vm.rollFork(vm.envUint("BLOCK_NUMBER"));

        Main main = new Main();
        (address flashLeverageCoreAddress, address flashLeverageAddress) = main
            .run();

        flc = IFlashLeverageCore(flashLeverageCoreAddress);
        fl = FlashLeverage(flashLeverageAddress);

        morpho = IMorpho(main.morpho());
        pendleRouter = main.pendleRouter();
        tokensConfig = main.getCollateralTokensConfig();
        liquidationBuffer = main.liquidationBuffer();
        slippageBuffer = main.slippageBuffer();
        treasury = main.treasury();
        USDC = main.USDC();

        _writeAddresses(address(flc), address(fl));
    }

    function getLeverageCalldata(
        address user,
        address collateralToken,
        address loanToken,
        uint256 desiredLtv,
        uint256 amountCollateral
    ) internal returns (bytes memory) {
        uint256 amountLeverageFlashLoan = flc.calcLeverageFlashLoan(
            desiredLtv,
            collateralToken,
            loanToken,
            amountCollateral
        );

        string memory url = string.concat(
            "http://127.0.0.1:3000/leverage",
            "?userAddress=",
            vm.toString(user),
            "&collateralTokenAddress=",
            vm.toString(collateralToken),
            "&amountCollateral=",
            vm.toString(amountCollateral),
            "&amountLeverageFlashLoan=",
            vm.toString(amountLeverageFlashLoan)
        );

        string[] memory inputs = new string[](6);
        inputs[0] = "curl";
        inputs[1] = "-s"; // Silent mode - no progress output
        inputs[2] = "--fail"; // Fail on HTTP errors
        inputs[3] = "-X";
        inputs[4] = "GET";
        inputs[5] = url;

        return vm.ffi(inputs);
    }

    function _writeAddresses(
        address flashLeverageCoreAddress,
        address flashLeverageAddress
    ) private {
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
        IERC20Metadata stblUSD = IERC20Metadata(USDC);
        vm.serializeAddress(usdcToken, "address", address(stblUSD));
        vm.serializeString(usdcToken, "name", stblUSD.name());
        vm.serializeString(usdcToken, "symbol", stblUSD.symbol());
        usdcToken = vm.serializeUint(usdcToken, "decimals", stblUSD.decimals());
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
            vm.serializeAddress(tokenObj, "oracleAddress", marketParams.oracle);
            vm.serializeString(tokenObj, "loanToken", loanTokenObj);
            tokenObj = vm.serializeAddress(
                tokenObj,
                "pendleMarketAddress",
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
            string.concat("./addresses/", vm.toString(block.chainid), ".json")
        );
    }

    function testSetup() external pure {} // To avoid compiler error
}
