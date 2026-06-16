// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import "./TestBase.sol";
import {UserProxy} from "src/core/FlashLeverage/UserProxy.sol";

interface IMerklDistributor {
    function toggleOperator(address user, address operator) external;
    function claim(
        address[] calldata users,
        address[] calldata tokens,
        uint256[] calldata amounts,
        bytes32[][] calldata proofs
    ) external;

    error NotWhitelisted();
    error InvalidProof();
}

/// @notice Fork tests proving that executeExternal + toggleOperator fixes the
///         NotWhitelisted() revert on the real Merkl distributor on mainnet.
///
///         Three assertions:
///         1. Before toggle → claim reverts NotWhitelisted (baseline, reproduces the bug)
///         2. After toggle  → claim reverts InvalidProof  (whitelist cleared, proof check reached)
///         3. Double toggle → operator revoked, back to NotWhitelisted (documents toggle semantics)
contract MerklForkTest is TestBase {
    address constant MERKL_DISTRIBUTOR = 0x3Ef3D8bA38EBe18DB133cEc108f4D14CE00Dd9Ae;

    UserProxy proxy;
    address proxyAddr;

    function setUp() public override {
        vm.createSelectFork("https://eth-mainnet.g.alchemy.com/v2/dP8O0bUE1anNSaJ9Bkub4GoVJoQMIflO");
        super.setUp();
        uint256 posId = _openCorrelatedPosition(alice, 10e18, 70e16);
        proxyAddr = fl.getUserLeveragePosition(alice, posId).userProxy;
        proxy = UserProxy(proxyAddr);
    }

    function _buildClaimArgs()
        internal
        view
        returns (
            address[] memory users,
            address[] memory tokens,
            uint256[] memory amounts,
            bytes32[][] memory proofs
        )
    {
        users = new address[](1);
        users[0] = proxyAddr;
        tokens = new address[](1);
        tokens[0] = address(loanToken);
        amounts = new uint256[](1);
        amounts[0] = 1e18;
        proofs = new bytes32[][](1);
        proofs[0] = new bytes32[](1);
        proofs[0][0] = bytes32(uint256(0xdeadbeef)); // intentionally fake
    }

    /// Reproduces the live bug: proxy is a contract with no operator set → NotWhitelisted.
    function test_merkl_beforeToggle_notWhitelisted() external {
        (
            address[] memory users,
            address[] memory tokens,
            uint256[] memory amounts,
            bytes32[][] memory proofs
        ) = _buildClaimArgs();

        vm.prank(alice);
        vm.expectRevert(IMerklDistributor.NotWhitelisted.selector);
        IMerklDistributor(MERKL_DISTRIBUTOR).claim(users, tokens, amounts, proofs);
    }

    /// The fix: executeExternal calls toggleOperator on Merkl from the proxy itself
    /// (msg.sender == proxy == user → passes Merkl's auth check).
    /// Claim now reaches the proof check → InvalidProof, never NotWhitelisted.
    function test_merkl_afterToggle_passesThroughToInvalidProof() external {
        vm.prank(alice);
        proxy.executeExternal(
            MERKL_DISTRIBUTOR,
            abi.encodeWithSignature("toggleOperator(address,address)", proxyAddr, alice)
        );

        (
            address[] memory users,
            address[] memory tokens,
            uint256[] memory amounts,
            bytes32[][] memory proofs
        ) = _buildClaimArgs();

        vm.prank(alice);
        vm.expectRevert(IMerklDistributor.InvalidProof.selector);
        IMerklDistributor(MERKL_DISTRIBUTOR).claim(users, tokens, amounts, proofs);
    }

    /// Calling toggle twice revokes the operator — documents the toggle semantics
    /// so the frontend knows never to call this twice.
    function test_merkl_toggleTwice_revokesOperator() external {
        vm.prank(alice);
        proxy.executeExternal(
            MERKL_DISTRIBUTOR,
            abi.encodeWithSignature("toggleOperator(address,address)", proxyAddr, alice)
        );
        vm.prank(alice);
        proxy.executeExternal(
            MERKL_DISTRIBUTOR,
            abi.encodeWithSignature("toggleOperator(address,address)", proxyAddr, alice)
        );

        (
            address[] memory users,
            address[] memory tokens,
            uint256[] memory amounts,
            bytes32[][] memory proofs
        ) = _buildClaimArgs();

        vm.prank(alice);
        vm.expectRevert(IMerklDistributor.NotWhitelisted.selector);
        IMerklDistributor(MERKL_DISTRIBUTOR).claim(users, tokens, amounts, proofs);
    }
}
