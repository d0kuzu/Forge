// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {DataTypes} from "../libraries/DataTypes.sol";

/// @title IGuildFactory — Interface for deterministic Guild deployment via CREATE2
/// @notice Factory pattern for deploying Guild mini-contracts with predictable addresses
interface IGuildFactory {
    error GuildAlreadyExists(address predicted);
    error InvalidGuildName();
    error ZeroAddress();

    event GuildCreated(address indexed guildAddress, string name, address indexed leader, bytes32 salt);

    /// @notice Deploy a new Guild contract deterministically using CREATE2
    /// @param name    Human-readable guild name
    /// @param leader  Address of the guild leader
    /// @param salt    Salt for deterministic address computation
    /// @return guildAddress  The deployed guild's address
    function createGuild(string calldata name, address leader, bytes32 salt)
        external returns (address guildAddress);

    /// @notice Predict the address of a guild before deployment
    /// @param name    Guild name (used in bytecode)
    /// @param leader  Guild leader address (used in bytecode)
    /// @param salt    Salt for computation
    /// @return predicted  The predicted contract address
    function predictGuildAddress(string calldata name, address leader, bytes32 salt)
        external view returns (address predicted);

    /// @notice Get a guild address by index
    function getGuild(uint256 index) external view returns (address);

    /// @notice Get total number of guilds deployed
    function getGuildCount() external view returns (uint256);

    /// @notice Check if an address is a guild deployed by this factory
    function isGuild(address addr) external view returns (bool);
}
