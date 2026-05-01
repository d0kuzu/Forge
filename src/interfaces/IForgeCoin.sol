// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IForgeCoin — Interface for the ForgeCoin ERC20 governance token
/// @notice Main ecosystem token with ERC20Permit, ERC20Votes extensions
/// @dev Inherits IERC20, IERC20Permit, IVotes from OpenZeppelin
interface IForgeCoin {
    // ============================================================
    //                         ERRORS
    // ============================================================

    /// @notice Caller does not have the MINTER_ROLE
    error NotMinter();

    /// @notice Mint would exceed the maximum supply cap
    error MaxSupplyExceeded();

    // ============================================================
    //                         EVENTS
    // ============================================================

    /// @notice Emitted when a new minter is authorized
    event MinterGranted(address indexed account);

    /// @notice Emitted when a minter's authorization is revoked
    event MinterRevoked(address indexed account);

    // ============================================================
    //                      MINTING / BURNING
    // ============================================================

    /// @notice Mint new ForgeCoin tokens
    /// @dev Only callable by addresses with MINTER_ROLE
    /// @param to        Recipient of the minted tokens
    /// @param amount    Amount to mint (18 decimals)
    function mint(address to, uint256 amount) external;

    /// @notice Burn tokens from the caller's balance
    /// @param amount    Amount to burn
    function burn(uint256 amount) external;

    /// @notice Burn tokens from another account (requires allowance)
    /// @param account   Address to burn tokens from
    /// @param amount    Amount to burn
    function burnFrom(address account, uint256 amount) external;

    // ============================================================
    //                    ROLE MANAGEMENT
    // ============================================================

    /// @notice Grant MINTER_ROLE to an address
    /// @dev Only callable by DEFAULT_ADMIN_ROLE (DAO Timelock)
    /// @param account   Address to grant minting rights to
    function grantMinterRole(address account) external;

    /// @notice Revoke MINTER_ROLE from an address
    /// @dev Only callable by DEFAULT_ADMIN_ROLE (DAO Timelock)
    /// @param account   Address to revoke minting rights from
    function revokeMinterRole(address account) external;

    // ============================================================
    //                      VIEW FUNCTIONS
    // ============================================================

    /// @notice Returns the maximum supply cap
    function maxSupply() external view returns (uint256);

    /// @notice Returns the MINTER_ROLE identifier
    function MINTER_ROLE() external view returns (bytes32);
}
