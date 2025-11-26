// // SPDX-License-Identifier: GPL-3.0-or-later
// pragma solidity 0.8.30;

// import {Test} from "forge-std/Test.sol";
// import {console} from "forge-std/console.sol";
// import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// import {WriteAddresses} from "../script/WriteAddresses.s.sol";
// import {IMorpho, MarketParams, Id, Position} from "@morpho/interfaces/IMorpho.sol";
// import {Main} from "../script/Main.s.sol";

// import "../src/core/FlashLeverage/FlashLeverageCore.sol";
// import "../src/core/FlashLeverage/FlashLeverage.sol";

// contract TestBase is Test, WriteAddresses {
//     FlashLeverageCore flc;
//     FlashLeverage fl;
//     IMorpho morpho;
//     address pendleRouter;
//     CollateralTokenConfig[] tokenConfigs;
//     address[] tokenWhales;
//     address treasury;
//     address USDC;
//     address RANDOM_ADDRESS;

//     /*//////////////////////////////////////////////////////////////
//                                CONSTANTS & IMMUTABLES
//     //////////////////////////////////////////////////////////////*/

//     uint256 internal constant AMOUNT_COLLATERAL = 10000e18; // 10k
//     uint256 internal constant DESIRED_LTV = 80e16; // 80%

//     uint256 internal constant TOKEN_INDEX = 0;
//     address internal USER;
//     address internal COLLATERAL_TOKEN;
//     address internal LOAN_TOKEN;
//     uint8 internal LOAN_TOKEN_DECIMALS;

//     function setUp() external virtual {
//         // Create fork
//         uint256 mainnetFork = vm.createFork(
//             "https://mainnet.infura.io/v3/34c180ccaea34433a2a35cb904afb19b"
//         );
//         vm.selectFork(mainnetFork);
//         vm.rollFork(vm.envUint("BLOCK_NUMBER"));

//         Main main = new Main();
//         (address flashLeverageCoreAddress, address flashLeverageAddress) = main
//             .run();

//         flc = FlashLeverageCore(flashLeverageCoreAddress);
//         fl = FlashLeverage(flashLeverageAddress);

//         morpho = IMorpho(main.morpho());
//         pendleRouter = main.pendleRouter();
//         tokenConfigs = main.getCollateralTokenConfigs();
//         tokenWhales = main.getCollateralTokenWhales();
//         treasury = main.treasury();
//         USDC = main.USDC();
//         RANDOM_ADDRESS = makeAddr("Random Address");

//         USER = tokenWhales[TOKEN_INDEX];
//         COLLATERAL_TOKEN = tokenConfigs[TOKEN_INDEX].collateralToken;
//         LOAN_TOKEN = morpho
//             .idToMarketParams(Id.wrap(tokenConfigs[TOKEN_INDEX].morphoMarketId))
//             .loanToken;
//         LOAN_TOKEN_DECIMALS = IERC20Metadata(LOAN_TOKEN).decimals();

//         _writeAddresses(
//             address(morpho),
//             tokenConfigs,
//             USDC,
//             address(flc),
//             address(fl),
//             "./api/test-addresses/"
//         );
//     }

//     function getLeverageCalldata(
//         address user,
//         uint256 desiredLtv,
//         address collateralToken,
//         address loanToken,
//         uint256 amountCollateral
//     ) internal returns (bytes memory) {
//         uint256 amountLeverageFlashLoan = flc.calcLeverageFlashLoan(
//             desiredLtv,
//             collateralToken,
//             loanToken,
//             amountCollateral
//         );

//         string memory url = string.concat(
//             "http://127.0.0.1:3000/flash-leverage/leverage",
//             "?userAddress=",
//             vm.toString(user),
//             "&desiredLtv=",
//             vm.toString(desiredLtv),
//             "&collateralTokenAddress=",
//             vm.toString(collateralToken),
//             "&amountCollateral=",
//             vm.toString(amountCollateral),
//             "&amountLeverageFlashLoan=",
//             vm.toString(amountLeverageFlashLoan)
//         );

//         string[] memory inputs = new string[](6);
//         inputs[0] = "curl";
//         inputs[1] = "-s"; // Silent mode - no progress output
//         inputs[2] = "--fail"; // Fail on HTTP errors
//         inputs[3] = "-X";
//         inputs[4] = "GET";
//         inputs[5] = url;

//         return vm.ffi(inputs);
//     }

//     function getUnleverageCalldata(
//         address user,
//         uint256 positionId,
//         address collateralToken,
//         uint256 amountLeveragedCollateral
//     ) internal returns (bytes memory) {
//         string memory url = string.concat(
//             "http://127.0.0.1:3000/flash-leverage/unleverage",
//             "?userAddress=",
//             vm.toString(user),
//             "&positionId=",
//             vm.toString(positionId),
//             "&collateralTokenAddress=",
//             vm.toString(collateralToken),
//             "&amountLeveragedCollateral=",
//             vm.toString(amountLeveragedCollateral)
//         );

//         string[] memory inputs = new string[](6);
//         inputs[0] = "curl";
//         inputs[1] = "-s"; // Silent mode - no progress output
//         inputs[2] = "--fail"; // Fail on HTTP errors
//         inputs[3] = "-X";
//         inputs[4] = "GET";
//         inputs[5] = url;

//         return vm.ffi(inputs);
//     }

//     function getCoreUnleverageCalldata(
//         address user,
//         uint256 desiredLtv,
//         address collateralToken,
//         uint256 sharesToBurn,
//         uint256 amountCollateralToWithdraw
//     ) internal returns (bytes memory) {
//         string memory url = string.concat(
//             "http://127.0.0.1:3000/flash-leverage-core/unleverage",
//             "?userAddress=",
//             vm.toString(user),
//             "&desiredLtv=",
//             vm.toString(desiredLtv),
//             "&collateralTokenAddress=",
//             vm.toString(collateralToken),
//             "&sharesToBurn=",
//             vm.toString(sharesToBurn),
//             "&amountCollateralToWithdraw=",
//             vm.toString(amountCollateralToWithdraw)
//         );

//         string[] memory inputs = new string[](6);
//         inputs[0] = "curl";
//         inputs[1] = "-s"; // Silent mode - no progress output
//         inputs[2] = "--fail"; // Fail on HTTP errors
//         inputs[3] = "-X";
//         inputs[4] = "GET";
//         inputs[5] = url;

//         return vm.ffi(inputs);
//     }

//     function _buildDefaultLeverageParams()
//         internal
//         returns (LeverageParams memory)
//     {
//         ApproxParams memory approxParams;
//         SwapData memory swapData;
//         LimitOrderData memory limitOrderData;

//         return
//             LeverageParams({
//                 desiredLtv: DESIRED_LTV,
//                 collateralToken: COLLATERAL_TOKEN,
//                 loanToken: LOAN_TOKEN,
//                 amountCollateral: AMOUNT_COLLATERAL,
//                 approxParams: approxParams,
//                 pendleSwap: makeAddr("pendleSwap"),
//                 tokenMintSy: makeAddr("tokenMintSy"),
//                 minPtOut: 0,
//                 swapData: swapData,
//                 limitOrderData: limitOrderData
//             });
//     }

//     function _buildDefaultUnleverageParams(
//         uint256 sharesToBurn,
//         uint256 amountCollateralToWithdraw
//     ) internal returns (UnleverageParams memory) {
//         SwapData memory swapData;
//         LimitOrderData memory limitOrderData;

//         return
//             UnleverageParams({
//                 desiredLtv: DESIRED_LTV,
//                 collateralToken: COLLATERAL_TOKEN,
//                 loanToken: LOAN_TOKEN,
//                 sharesToBurn: sharesToBurn,
//                 amountCollateralToWithdraw: amountCollateralToWithdraw,
//                 pendleSwap: makeAddr("pendleSwap"),
//                 tokenRedeemSy: makeAddr("tokenRedeemSy"),
//                 minTokenOut: 0,
//                 swapData: swapData,
//                 limitOrderData: limitOrderData
//             });
//     }

//     function testSetup() external pure {} // To avoid compiler error
// }
