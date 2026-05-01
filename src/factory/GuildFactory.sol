// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Guild} from "./Guild.sol";

/// @title GuildFactory — Deterministic Guild Deployment via CREATE2
/// @notice Deploys Guild mini-contracts with predictable addresses using the
///         CREATE2 opcode. Anyone can create a guild by providing a name,
///         leader address, and salt for deterministic address computation.
/// @dev The predicted address depends on: factory address, salt, and init code hash.
///      The init code includes constructor args (name, leader), making the address
///      unique per guild configuration.
contract GuildFactory {
    // ============================================================
    //                       STORAGE
    // ============================================================

    /// @notice Array of all deployed guild addresses
    address[] private _guilds;

    /// @notice address => whether it was deployed by this factory
    mapping(address => bool) public isGuild;

    // ============================================================
    //                      CUSTOM ERRORS
    // ============================================================

    error GuildAlreadyExists(address predicted);
    error InvalidGuildName();
    error ZeroAddress();
    error GuildDeploymentFailed();

    // ============================================================
    //                         EVENTS
    // ============================================================

    event GuildCreated(
        address indexed guildAddress,
        string name,
        address indexed leader,
        bytes32 salt,
        uint256 guildIndex
    );

    // ============================================================
    //                   GUILD DEPLOYMENT
    // ============================================================

    /// @notice Deploy a new Guild contract deterministically using CREATE2
    /// @param name    Human-readable guild name (must not be empty)
    /// @param leader  Address of the guild leader
    /// @param salt    Salt for deterministic address computation
    /// @return guildAddress  The deployed guild's address
    function createGuild(
        string calldata name,
        address leader,
        bytes32 salt
    ) external returns (address guildAddress) {
        if (bytes(name).length == 0) revert InvalidGuildName();
        if (leader == address(0)) revert ZeroAddress();

        // Compute the creation bytecode with constructor arguments
        bytes memory bytecode = abi.encodePacked(
            type(Guild).creationCode,
            abi.encode(name, leader)
        );

        // Deploy using CREATE2
        assembly {
            guildAddress := create2(0, add(bytecode, 0x20), mload(bytecode), salt)
        }

        if (guildAddress == address(0)) revert GuildDeploymentFailed();

        // Verify no duplicate (should be impossible with CREATE2, but defensive)
        if (isGuild[guildAddress]) revert GuildAlreadyExists(guildAddress);

        isGuild[guildAddress] = true;
        _guilds.push(guildAddress);

        emit GuildCreated(guildAddress, name, leader, salt, _guilds.length - 1);
    }

    // ============================================================
    //                    ADDRESS PREDICTION
    // ============================================================

    /// @notice Predict the address of a guild before deployment
    /// @dev Uses CREATE2 address formula: keccak256(0xff ++ factory ++ salt ++ keccak256(bytecode))
    /// @param name    Guild name (must match what will be passed to createGuild)
    /// @param leader  Guild leader (must match)
    /// @param salt    Salt (must match)
    /// @return predicted  The predicted contract address
    function predictGuildAddress(
        string calldata name,
        address leader,
        bytes32 salt
    ) external view returns (address predicted) {
        bytes memory bytecode = abi.encodePacked(
            type(Guild).creationCode,
            abi.encode(name, leader)
        );

        bytes32 bytecodeHash = keccak256(bytecode);

        // CREATE2 address = keccak256(0xff ++ deployer ++ salt ++ bytecodeHash)[12:]
        predicted = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(bytes1(0xff), address(this), salt, bytecodeHash)
                    )
                )
            )
        );
    }

    // ============================================================
    //                      VIEW FUNCTIONS
    // ============================================================

    /// @notice Get a guild address by index
    function getGuild(uint256 index) external view returns (address) {
        return _guilds[index];
    }

    /// @notice Get total number of guilds deployed
    function getGuildCount() external view returns (uint256) {
        return _guilds.length;
    }

    /// @notice Get all guild addresses
    function getAllGuilds() external view returns (address[] memory) {
        return _guilds;
    }
}
