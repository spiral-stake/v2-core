// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import {Math} from "../src/core/libraries/Math.sol";
import {MarketConfig} from "../src/core/structs/MarketConfig.sol";

import {WriteAddresses} from "../script/WriteAddresses.s.sol";
import {IMorpho, MarketParams, Id, Position} from "@morpho/interfaces/IMorpho.sol";
import "../script/Main.s.sol";

import "../src/core/FlashLeverage/FlashLeverage.sol";

contract TestBase is Test, WriteAddresses, Config {
    using Math for uint256;

    FlashLeverage fl;
    IMorpho morpho;
    MarketConfig[] marketConfigs;
    address[] tokenWhales;
    address treasury;
    address USDC;
    address RANDOM_ADDRESS;

    /*//////////////////////////////////////////////////////////////
                               CONSTANTS & IMMUTABLES
    //////////////////////////////////////////////////////////////*/

    uint256 internal constant AMOUNT_COLLATERAL = 10000e18; // 10k
    uint256 internal constant DESIRED_LTV = 70e16; // 70%

    bytes32 internal marketId;
    MarketParams internal market;
    uint256 internal constant TOKEN_INDEX = 0; // Collateral Token to run the tests on
    address internal USER;
    uint8 internal LOAN_TOKEN_DECIMALS;

    function setUp() external virtual {
        // Create fork
        uint256 mainnetFork = vm.createFork(
            "https://mainnet.infura.io/v3/34c180ccaea34433a2a35cb904afb19b"
        );
        vm.selectFork(mainnetFork);
        vm.rollFork(vm.envUint("BLOCK_NUMBER"));

        fl = FlashLeverage(new Main().run());
        ChainConfig memory chain = getChainConfig();

        morpho = IMorpho(chain.morpho);
        marketConfigs = getMarketConfigs();
        tokenWhales = getCollateralTokenWhales();
        treasury = chain.treasury;
        USDC = chain.USDC;
        RANDOM_ADDRESS = makeAddr("Random Address");
        marketId = marketConfigs[TOKEN_INDEX].marketId;
        market = morpho.idToMarketParams(Id.wrap(marketId));

        USER = tokenWhales[TOKEN_INDEX];

        LOAN_TOKEN_DECIMALS = IERC20Metadata(market.loanToken).decimals();

        _writeAddresses(
            address(morpho),
            marketConfigs,
            address(fl),
            address(0),
            "./api/test-addresses/"
        );
    }

    function getLeverageCalldata(
        address user,
        uint256 desiredLtv,
        uint256 amountCollateral
    ) internal returns (bytes memory) {
        uint256 amountFlashLoan = _calcLeverageFlashLoan(
            desiredLtv,
            amountCollateral
        );

        string memory url = string.concat(
            "http://127.0.0.1:3000/leverage",
            "?userAddress=",
            vm.toString(user),
            "&collateralTokenAddress=",
            vm.toString(market.collateralToken),
            "&amountCollateral=",
            vm.toString(amountCollateral),
            "&amountFlashLoan=",
            vm.toString(amountFlashLoan)
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

    function getDeleverageCalldata(
        uint256 positionId,
        uint256 amountLeveragedCollateral
    ) internal returns (bytes memory) {
        string memory url = string.concat(
            "http://127.0.0.1:3000/deleverage",
            "?positionId=",
            vm.toString(positionId),
            "&collateralTokenAddress=",
            vm.toString(market.collateralToken),
            "&amountLeveragedCollateral=",
            vm.toString(amountLeveragedCollateral)
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

    function _buildDefaultLeverageParams()
        internal
        view
        returns (LeverageParams memory)
    {
        SwapData memory swapData;
        return
            LeverageParams({
                marketId: marketId,
                amountCollateral: AMOUNT_COLLATERAL,
                amountFlashLoan: 0,
                swapData: swapData,
                minTokenOut: 0
            });
    }

    /**
     * @notice Calculates the flashloan amount needed for leveraging based on desired LTV and collateral amount.
     * @param desiredLtv The desired loan-to-value ratio for the position.
     * @param amountCollateral Amount of collateral being supplied.
     * @return amountToBorrow Amount of loanToken that can be borrowed (scaled to loanToken decimals).
     */
    function _calcLeverageFlashLoan(
        uint256 desiredLtv,
        uint256 amountCollateral
    ) internal view returns (uint256) {
        uint256 collateralValue = fl
            .getCollateralValueInLoanToken(market, amountCollateral)
            .scaleTo(LOAN_TOKEN_DECIMALS, Math.STANDARD_DECIMALS);

        // Total position value = collateralValue / (1 - LTV)
        uint256 totalPositionValue = collateralValue.divDown(
            Math.ONE - desiredLtv
        );

        // Loan amount = total position - collateral
        uint256 amountLoan = totalPositionValue - collateralValue;

        return amountLoan.scaleTo(Math.STANDARD_DECIMALS, LOAN_TOKEN_DECIMALS);
    }

    function testSetup() external pure {} // To avoid compiler error
}
