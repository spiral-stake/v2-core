// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";
import {StblUSD, IStblUSD} from "../src/core/borrow/StblUSD.sol";
import {PositionManager} from "../src/core/borrow/PositionManager.sol";

contract DeployPositionManager is Script {
    function run(
        address stblUSDAddress,
        address[] memory collateralTokens,
        address[] memory priceFeeds,
        address treasury
    ) external returns (address positionManagerAddress) {
        vm.startBroadcast();

        positionManagerAddress = address(
            new PositionManager(address(stblUSDAddress), treasury)
        );

        // Setting Position manager as StblUSD minter
        IStblUSD(stblUSDAddress).setManagerAddresses(positionManagerAddress);

        // Adding supported collateral tokens
        PositionManager(positionManagerAddress).addSupportedCollateralTokens(
            collateralTokens,
            priceFeeds
        );

        vm.stopBroadcast();
    }
}

// address stblUSDAddress = 0x1c7b129Dc0c3cced44442dcbC1abBCc7c7962801;
// positionManagerAddress = address(
//     new PositionManager(stblUSDAddress, makeAddr("treasury"))
// );

// Setting Position manager as StblUSD minter
// IStblUSD(stblUSDAddress).setManagerAddresses(positionManagerAddress);

// address[] memory collateralTokens = new address[](5);
// collateralTokens[0] = 0x1b922B45fd00D1d1E524538B45c963bC0C325189;
// collateralTokens[1] = 0x3d3aF2eCfaa71343B15aCf5D64d6fbBC2B22AD26;
// collateralTokens[2] = 0xb97e2Eaff562b702cB744352Da05646b6e9DD65F;
// collateralTokens[3] = 0xE4408cECD1eC5D8336b16998f010cf4f8497AB23;
// collateralTokens[4] = 0xb4ccD7d85bC96E6F260671E5f218B615a5cC62D9;

// address[] memory priceFeeds = new address[](5);
// priceFeeds[0] = 0x2DAcfcf449a21Bb005E20938C021afc8712c4D46;
// priceFeeds[1] = 0xF319f86A3106d7D5Fc85D414366aC05cCB38376D;
// priceFeeds[2] = 0x91d1F2b67f85E559960052Cf4980990ED15Ebc34;
// priceFeeds[3] = 0x9DF1CbfE7C596aedF405523D008f019be98e7983;
// priceFeeds[4] = 0xf6b317cFF0727ED95D92b1AfDdB6178C025e2Ae7;

// // Adding supported collateral tokens
// PositionManager(positionManagerAddress).addSupportedCollateralTokens(
//     collateralTokens,
//     priceFeeds
// );
