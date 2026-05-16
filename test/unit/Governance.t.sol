// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {ForgeCoin} from "../../src/tokens/ForgeCoin.sol";
import {ForgeGovernor} from "../../src/governance/ForgeGovernor.sol";
import {ForgeTimelock} from "../../src/governance/ForgeTimelock.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";

contract GovernanceTest is Test {
    ForgeCoin public coin;
    ForgeTimelock public timelock;
    ForgeGovernor public governor;

    address public admin = address(this);
    address public proposer = address(0x1111);
    address public voter1 = address(0x2222);
    address public voter2 = address(0x3333);

    function setUp() public {
        coin = new ForgeCoin(admin, 1_000_000 * 1e18);

        // 1. Deploy Timelock with 2-block delay
        address[] memory proposers = new address[](1);
        proposers[0] = admin;
        address[] memory executors = new address[](1);
        executors[0] = address(0); // Anyone can execute

        timelock = new ForgeTimelock(
            2, // minDelay
            proposers,
            executors,
            admin
        );

        // 2. Deploy Governor (votingDelay = 1 block, votingPeriod = 5 blocks, threshold = 1000 tokens, quorum = 4%)
        governor = new ForgeGovernor(
            coin,
            timelock,
            1, // votingDelay
            5, // votingPeriod
            1000 * 1e18, // proposalThreshold
            4 // quorumPercent
        );

        // Grant roles to governor in timelock
        bytes32 proposerRole = timelock.PROPOSER_ROLE();
        bytes32 cancellerRole = timelock.CANCELLER_ROLE();
        bytes32 executorRole = timelock.EXECUTOR_ROLE();

        timelock.grantRole(proposerRole, address(governor));
        timelock.grantRole(cancellerRole, address(governor));
        timelock.grantRole(executorRole, address(governor));

        // Grant minter role of coin to timelock so it can execute mint proposals
        coin.grantRole(coin.MINTER_ROLE(), address(timelock));

        // Revoke admin powers from deployer to make it truly decentralized
        // timelock.revokeRole(timelock.DEFAULT_ADMIN_ROLE(), admin); // skip to keep admin powers in test

        // Fund users and set checkpoints
        coin.transfer(proposer, 5000 * 1e18);
        coin.transfer(voter1, 50_000 * 1e18);
        coin.transfer(voter2, 30_000 * 1e18);

        vm.prank(proposer);
        coin.delegate(proposer);

        vm.prank(voter1);
        coin.delegate(voter1);

        vm.prank(voter2);
        coin.delegate(voter2);

        // Mine 1 block to ensure checkpoints are written
        vm.roll(block.number + 1);
    }

    // --- Unit Tests ---

    function test_ProposalLifecycle() public {
        address[] memory targets = new address[](1);
        targets[0] = address(coin);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(ForgeCoin.mint.selector, address(this), 100);
        string memory desc = "Proposal #1: Mint 100 tokens to admin";

        // 1. Propose
        vm.prank(proposer);
        uint256 propId = governor.propose(targets, values, calldatas, desc);

        assertEq(uint8(governor.state(propId)), 0); // Pending

        // Roll to start voting
        vm.roll(block.number + governor.votingDelay() + 1);
        assertEq(uint8(governor.state(propId)), 1); // Active

        // 2. Vote
        vm.prank(voter1);
        governor.castVote(propId, 1); // For

        vm.prank(voter2);
        governor.castVote(propId, 0); // Against

        // Roll to end voting
        vm.roll(block.number + governor.votingPeriod() + 1);
        assertEq(uint8(governor.state(propId)), 4); // Succeeded

        // 3. Queue
        governor.queue(targets, values, calldatas, keccak256(bytes(desc)));
        assertEq(uint8(governor.state(propId)), 5); // Queued

        // Warp time for timelock execution delay
        vm.warp(block.timestamp + 10);

        // 4. Execute
        governor.execute(targets, values, calldatas, keccak256(bytes(desc)));
        assertEq(uint8(governor.state(propId)), 7); // Executed
    }

    function test_CancelProposal() public {
        address[] memory targets = new address[](1);
        targets[0] = address(coin);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(ForgeCoin.mint.selector, address(this), 100);
        string memory desc = "Proposal #2: Mint tokens to admin";

        vm.prank(proposer);
        uint256 propId = governor.propose(targets, values, calldatas, desc);

        // Proposer can cancel
        vm.prank(proposer);
        governor.cancel(targets, values, calldatas, keccak256(bytes(desc)));
        assertEq(uint8(governor.state(propId)), 2); // Canceled
    }

    function test_VotingDelayAndPeriod() public view {
        assertEq(governor.votingDelay(), 1);
        assertEq(governor.votingPeriod(), 5);
        assertEq(governor.proposalThreshold(), 1000 * 1e18);
    }

    function test_RevertExecuteWithoutQueue() public {
        address[] memory targets = new address[](1);
        targets[0] = address(coin);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(ForgeCoin.mint.selector, address(this), 100);
        string memory desc = "Proposal #3: Revert execute without queue";

        vm.prank(proposer);
        uint256 propId = governor.propose(targets, values, calldatas, desc);

        vm.roll(block.number + governor.votingDelay() + 1);

        vm.prank(voter1);
        governor.castVote(propId, 1);

        vm.roll(block.number + governor.votingPeriod() + 1);

        // Attempt to execute without queueing first
        vm.expectRevert();
        governor.execute(targets, values, calldatas, keccak256(bytes(desc)));
    }

    // --- Fuzz Tests ---

    function testFuzz_ProposalThreshold(uint256 balance) public {
        balance = bound(balance, 0, 999 * 1e18);
        
        address poorUser = address(0x5555);
        coin.transfer(poorUser, balance);
        vm.prank(poorUser);
        coin.delegate(poorUser);

        vm.roll(block.number + 1);

        address[] memory targets = new address[](1);
        targets[0] = address(coin);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(ForgeCoin.mint.selector, address(this), 100);

        vm.prank(poorUser);
        vm.expectRevert(); // should revert due to insufficient proposal threshold
        governor.propose(targets, values, calldatas, "Low balance proposal");
    }
}
