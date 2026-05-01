// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

/// @title ForgeTimelock — Timelock Controller for Decentralized Forge DAO
/// @notice Enforces a delay on all DAO-approved proposals before execution.
///         This contract holds the admin roles (DEFAULT_ADMIN_ROLE) for ForgeCoin,
///         ForgeItems, GachaLootbox, and other ecosystem contracts.
/// @dev Wrapper around OZ TimelockController v5. The ForgeGovernor is set as
///      the sole proposer and executor. Self-administration ensures the timelock
///      can update its own delay via governance.
contract ForgeTimelock is TimelockController {
    /// @notice Deploy the ForgeTimelock
    /// @param minDelay      Minimum delay (in seconds) before execution, e.g. 86400 (1 day)
    /// @param proposers     Addresses allowed to propose (should include ForgeGovernor)
    /// @param executors     Addresses allowed to execute (should include ForgeGovernor)
    /// @param admin         Optional admin address (address(0) to disable separate admin)
    constructor(
        uint256 minDelay,
        address[] memory proposers,
        address[] memory executors,
        address admin
    ) TimelockController(minDelay, proposers, executors, admin) {}
}
