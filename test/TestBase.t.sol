// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";

import {WriteAddresses} from "../script/WriteAddresses.s.sol";
import {IMorpho, MarketParams, Id, Position} from "@morpho/interfaces/IMorpho.sol";
import {Main} from "../script/Main.s.sol";

import "../src/core/FlashLeverage/FlashLeverageCore.sol";
import "../src/core/FlashLeverage/FlashLeverage.sol";

contract TestBase is Test, WriteAddresses {
    FlashLeverageCore flc;
    FlashLeverage fl;
    IMorpho morpho;
    address pendleRouter;
    CollateralTokenConfig[] tokensConfig;
    uint256 liquidationBuffer;
    uint256 slippageBuffer;
    address treasury;
    address USDC;
    address RANDOM_ADDRESS;

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

        flc = FlashLeverageCore(flashLeverageCoreAddress);
        fl = FlashLeverage(flashLeverageAddress);

        morpho = IMorpho(main.morpho());
        pendleRouter = main.pendleRouter();
        tokensConfig = main.getCollateralTokensConfig();
        liquidationBuffer = main.liquidationBuffer();
        slippageBuffer = main.slippageBuffer();
        treasury = main.treasury();
        USDC = main.USDC();
        RANDOM_ADDRESS = makeAddr("Random Address");

        _writeAddresses(
            address(morpho),
            tokensConfig,
            USDC,
            address(flc),
            address(fl),
            "./api/test-addresses/"
        );
    }

    function getLeverageCalldata(
        address user,
        uint256 desiredLtv,
        address collateralToken,
        address loanToken,
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
            "&desiredLtv=",
            vm.toString(desiredLtv),
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

    function getUnleverageCalldata(
        address user,
        uint256 desiredLtv,
        address collateralToken,
        uint256 sharesToBurn,
        uint256 amountCollateralToWithdraw
    ) internal returns (bytes memory) {
        string memory url = string.concat(
            "http://127.0.0.1:3000/unleverage",
            "?userAddress=",
            vm.toString(user),
            "&desiredLtv=",
            vm.toString(desiredLtv),
            "&collateralTokenAddress=",
            vm.toString(collateralToken),
            "&sharesToBurn=",
            vm.toString(sharesToBurn),
            "&amountCollateralToWithdraw=",
            vm.toString(amountCollateralToWithdraw)
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

    function testSetup() external pure {} // To avoid compiler error
}
