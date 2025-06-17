// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import {ISPIUSD} from "../../interfaces/ISPIUSD.sol";
import {IERC3156FlashBorrower} from "@openzeppelin/contracts/interfaces/IERC3156FlashBorrower.sol";
import {IERC3156FlashLender} from "@openzeppelin/contracts/interfaces/IERC3156FlashLender.sol";
import {Errors} from "../libraries/Errors.sol";

contract FlashBorrower is IERC3156FlashBorrower {
    IERC3156FlashLender lender;

    /// @notice Reference to the SPIUSD stablecoin contract
    ISPIUSD public immutable SPIUSD;

    constructor(IERC3156FlashLender lender_) {
        lender = lender_;
    }

    /// @dev ERC-3156 Flash loan callback
    function onFlashLoan(
        address initiator,
        address token,
        uint256 amount,
        uint256 fee,
        bytes calldata data
    ) external override returns (bytes32) {
        require(
            msg.sender == address(lender),
            Errors.FlashLeverage__UntrustedLender()
        );
        require(
            initiator == address(this),
            Errors.FlashLeverage__UntrustedLoanInitiator()
        );
        require(
            token == address(SPIUSD),
            Errors.FlashLeverage__InvalidLoanToken()
        );
        require(
            SPIUSD.balanceOf(address(this)) >= amount,
            Errors.FlashLeverage__InvalidLoanAmount()
        );

        address leverageToken = abi.decode(data, (address));

        // Leverage staked stables with borrowed SPIUSD

        // swap SPIUSD for respective staked stable

        // and deposit the purchased staked stable as collateral to mint SPIUSD

        // and repay the loan

        SPIUSD.transfer(initiator, amount + fee);
        return keccak256("ERC3156FlashBorrower.onFlashLoan");
    }

    /// @dev Initiate a flash loan
    function flashLeverage(
        address leverageToken,
        uint256 amountLeverage
    ) public {
        uint256 amountLoan = 0; // Calc loan amount

        uint256 _fee = lender.flashFee(address(SPIUSD), amountLoan);
        uint256 _repayment = amountLoan + _fee;

        SPIUSD.approve(address(lender), _repayment);
        lender.flashLoan(
            this,
            address(SPIUSD),
            amountLoan,
            abi.encode(leverageToken)
        );
    }
}
