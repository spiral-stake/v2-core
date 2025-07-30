// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";
import {FlashLeverage, CollateralTokenData, LeverageParams, LeveragePosition, ApproxParams, SwapData, SwapParams, LimitOrderData} from "../src/core/leverage/FlashLeverage.sol";
import {SwapAggregator, IPAllActionV3, SwapType} from "../src/core/leverage/SwapAggregator.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

contract Test is Script, SwapAggregator {
    address pendleRouter = 0x888888888889758F76e7103c6CbF23ABbF58F946;

    constructor() SwapAggregator(pendleRouter) {}
}
