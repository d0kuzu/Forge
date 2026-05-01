// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Governor} from "@openzeppelin/contracts/governance/Governor.sol";
import {GovernorSettings} from "@openzeppelin/contracts/governance/extensions/GovernorSettings.sol";
import {GovernorCountingSimple} from "@openzeppelin/contracts/governance/extensions/GovernorCountingSimple.sol";
import {GovernorVotes} from "@openzeppelin/contracts/governance/extensions/GovernorVotes.sol";
import {GovernorVotesQuorumFraction} from "@openzeppelin/contracts/governance/extensions/GovernorVotesQuorumFraction.sol";
import {GovernorTimelockControl} from "@openzeppelin/contracts/governance/extensions/GovernorTimelockControl.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";

/// @title ForgeGovernor — DAO Governance for Decentralized Forge
/// @notice Full on-chain governance for managing critical game parameters:
///         - Drop rates in GachaLootbox
///         - Crafting costs in ForgeItems
///         - Role management across all contracts
/// @dev Uses OZ Governor v5 with extensions:
///      - GovernorSettings: configurable voting delay, period, threshold
///      - GovernorCountingSimple: For/Against/Abstain voting
///      - GovernorVotes: voting power from ForgeCoin (ERC20Votes)
///      - GovernorVotesQuorumFraction: quorum as % of total supply
///      - GovernorTimelockControl: execution delay via TimelockController
contract ForgeGovernor is
    Governor,
    GovernorSettings,
    GovernorCountingSimple,
    GovernorVotes,
    GovernorVotesQuorumFraction,
    GovernorTimelockControl
{
    /// @notice Deploy the ForgeGovernor
    /// @param _token        ForgeCoin token with ERC20Votes (voting power source)
    /// @param _timelock     TimelockController for delayed execution
    /// @param votingDelay_  Delay before voting starts (in blocks), e.g. 7200 (~1 day)
    /// @param votingPeriod_ Duration of voting (in blocks), e.g. 50400 (~1 week)
    /// @param proposalThreshold_ Min tokens required to create a proposal, e.g. 1000e18
    /// @param quorumPercent_     Quorum as % of total supply, e.g. 4 (= 4%)
    constructor(
        IVotes _token,
        TimelockController _timelock,
        uint48 votingDelay_,
        uint32 votingPeriod_,
        uint256 proposalThreshold_,
        uint256 quorumPercent_
    )
        Governor("ForgeGovernor")
        GovernorSettings(votingDelay_, votingPeriod_, proposalThreshold_)
        GovernorVotes(_token)
        GovernorVotesQuorumFraction(quorumPercent_)
        GovernorTimelockControl(_timelock)
    {}

    // ============================================================
    //               REQUIRED OVERRIDES (Solidity)
    // ============================================================

    function votingDelay()
        public
        view
        override(Governor, GovernorSettings)
        returns (uint256)
    {
        return super.votingDelay();
    }

    function votingPeriod()
        public
        view
        override(Governor, GovernorSettings)
        returns (uint256)
    {
        return super.votingPeriod();
    }

    function quorum(uint256 blockNumber)
        public
        view
        override(Governor, GovernorVotesQuorumFraction)
        returns (uint256)
    {
        return super.quorum(blockNumber);
    }

    function state(uint256 proposalId)
        public
        view
        override(Governor, GovernorTimelockControl)
        returns (ProposalState)
    {
        return super.state(proposalId);
    }

    function proposalNeedsQueuing(uint256 proposalId)
        public
        view
        override(Governor, GovernorTimelockControl)
        returns (bool)
    {
        return super.proposalNeedsQueuing(proposalId);
    }

    function proposalThreshold()
        public
        view
        override(Governor, GovernorSettings)
        returns (uint256)
    {
        return super.proposalThreshold();
    }

    function _queueOperations(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) returns (uint48) {
        return super._queueOperations(proposalId, targets, values, calldatas, descriptionHash);
    }

    function _executeOperations(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) {
        super._executeOperations(proposalId, targets, values, calldatas, descriptionHash);
    }

    function _cancel(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) returns (uint256) {
        return super._cancel(targets, values, calldatas, descriptionHash);
    }

    function _executor()
        internal
        view
        override(Governor, GovernorTimelockControl)
        returns (address)
    {
        return super._executor();
    }
}
