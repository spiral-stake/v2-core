// // SPDX-License-Identifier: GPL-3.0-or-later
// pragma solidity 0.8.30;

// import {IPositionManager} from "../interfaces/IPositionManager.sol";
// import {IERC3156FlashBorrower} from "@openzeppelin/contracts/interfaces/IERC3156FlashBorrower.sol";
// import {IERC3156FlashLender} from "@openzeppelin/contracts/interfaces/IERC3156FlashLender.sol";
// import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
// import {AggregatorV3Interface} from "@chainlink";
// import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
// import {TokenHelper} from "../core/libraries/TokenHelper.sol";
// import {ICurveCryptoSwap} from "../interfaces/ICurveCryptoSwap.sol";

// /**
//  * @title Borrow Swapper
//  * @notice This contract is used when a user borrows or mints stblUSD from the PositionManager
//  * and wants to automatically swap it to a supported token via its respective Curve pool.
//  */

// contract BorrowSwapper is Ownable2Step, TokenHelper {
//     IPositionManager private immutable i_positionManager;
//     address private immutable i_stblUSD;

//     mapping(address swapToken => address curvePool) s_curvePools;

//     constructor(address positionManager) Ownable(msg.sender) {
//         i_positionManager = IPositionManager(positionManager);
//         i_stblUSD = i_positionManager.getStblUSD();
//     }

//     function openPosition(
//         address collateralToken,
//         address swapToken,
//         uint256 amountCollateral,
//         uint256 amountToMint
//     ) external returns (uint256 positionId) {
//         _transferIn(collateralToken, msg.sender, amountCollateral);
//         _safeApprove(
//             collateralToken,
//             address(i_positionManager),
//             amountCollateral
//         );

//         positionId = i_positionManager.openPosition(
//             collateralToken,
//             amountCollateral,
//             amountToMint
//         );

//         ICurveCryptoSwap curvePool = ICurveCryptoSwap(s_curvePools[swapToken]);
//         _safeApprove(i_stblUSD, address(curvePool), amountToMint);
//         curvePool.exchange(1, 0, amountToMint, 0, msg.sender);

//         i_positionManager.updatePositionOwner(positionId, msg.sender);
//     }

//     function addSupportedTokens(
//         address[] memory tokens,
//         address[] memory curvePools
//     ) external onlyOwner {
//         require(tokens.length == curvePools.length, "Length Mismatch");

//         for (uint256 i = 0; i < tokens.length; ++i) {
//             require(tokens[i] != address(0), "Invalid Token Address");
//             s_curvePools[tokens[i]] = curvePools[i];
//         }
//     }
// }
