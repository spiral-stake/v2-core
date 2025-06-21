// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";
import {SPIUSD, ISPIUSD} from "../src/core/SPIUSD/SPIUSD.sol";
import {PositionManager} from "../src/core/SPIUSD/PositionManager.sol";

contract DeployPositionManager is Script {
    function run(
        address spiUsdAddress,
        address[] memory collateralTokens,
        address[] memory priceFeeds,
        address treasury
    ) external returns (address positionManagerAddress) {
        vm.startBroadcast();

        positionManagerAddress = address(
            new PositionManager(address(spiUsdAddress), treasury)
        );

        // Setting Position manager as SPIUSD minter
        ISPIUSD(spiUsdAddress).setManagerAddresses(positionManagerAddress);

        // Adding supported collateral tokens
        PositionManager(positionManagerAddress).addSupportedCollateralTokens(
            collateralTokens,
            priceFeeds
        );

        // address spiUsdAddress = 0xdBcEA9CE3997479C7434D5F20EA4428Bb29cB865;
        // positionManagerAddress = address(
        //     new PositionManager(spiUsdAddress, makeAddr("treasury"))
        // );

        // // Setting Position manager as SPIUSD minter
        // ISPIUSD(spiUsdAddress).setManagerAddresses(positionManagerAddress);

        // address[] memory collateralTokens = new address[](3);
        // collateralTokens[0] = 0xE4408cECD1eC5D8336b16998f010cf4f8497AB23;
        // collateralTokens[1] = 0x26b8fAb1a8179822a3D8df35A063f38913904614;
        // collateralTokens[2] = 0xb4ccD7d85bC96E6F260671E5f218B615a5cC62D9;

        // address[] memory priceFeeds = new address[](3);
        // priceFeeds[0] = 0x9DF1CbfE7C596aedF405523D008f019be98e7983;
        // priceFeeds[1] = 0x78a5075468Cd926789Ab5a67c81D2f8973AB6b19;
        // priceFeeds[2] = 0xf6b317cFF0727ED95D92b1AfDdB6178C025e2Ae7;

        // // Adding supported collateral tokens
        // PositionManager(positionManagerAddress).addSupportedCollateralTokens(
        //     collateralTokens,
        //     priceFeeds
        // );

        vm.stopBroadcast();
    }
}

// vm.startBroadcast();
// // spiUsdAddress = address(new SPIUSD());
// positionManagerAddress = address(
//     new PositionManager(
//         0xdBcEA9CE3997479C7434D5F20EA4428Bb29cB865,
//         makeAddr("treasury")
//     )
// );

// // Setting Position manager as SPIUSD minter
// ISPIUSD(0xdBcEA9CE3997479C7434D5F20EA4428Bb29cB865).setManagerAddresses(
//         positionManagerAddress
//     );

// address[] memory collateralTokens = new address[](3);
// collateralTokens[0] = 0xE4408cECD1eC5D8336b16998f010cf4f8497AB23;
// collateralTokens[1] = 0x26b8fAb1a8179822a3D8df35A063f38913904614;
// collateralTokens[2] = 0xb4ccD7d85bC96E6F260671E5f218B615a5cC62D9;

// address[] memory priceFeeds = new address[](3);
// priceFeeds[0] = 0x9DF1CbfE7C596aedF405523D008f019be98e7983;
// priceFeeds[1] = 0x78a5075468Cd926789Ab5a67c81D2f8973AB6b19;
// priceFeeds[2] = 0xf6b317cFF0727ED95D92b1AfDdB6178C025e2Ae7;

// // Adding supported collateral tokens
// PositionManager(positionManagerAddress).addSupportedCollateralTokens(
//     collateralTokens,
//     priceFeeds
// );
// vm.stopBroadcast();
