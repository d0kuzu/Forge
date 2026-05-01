// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {ERC20Votes} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Nonces} from "@openzeppelin/contracts/utils/Nonces.sol";

/// @title ForgeCoin — ERC20 Governance Token for Decentralized Forge
/// @notice Main ecosystem token with ERC20Permit (gasless approvals) and ERC20Votes (DAO voting)
/// @dev Role-based minting via AccessControl. DEFAULT_ADMIN_ROLE is transferred to DAO Timelock.
///      Max supply is capped at 100 million tokens.
contract ForgeCoin is ERC20, ERC20Burnable, ERC20Permit, ERC20Votes, AccessControl {
    // ============================================================
    //                       CONSTANTS
    // ============================================================

    /// @notice Role identifier for addresses authorized to mint tokens
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    /// @notice Maximum total supply: 100,000,000 tokens (18 decimals)
    uint256 public constant MAX_SUPPLY = 100_000_000 * 1e18;

    // ============================================================
    //                      CUSTOM ERRORS
    // ============================================================

    /// @notice Mint would exceed the maximum supply cap
    error MaxSupplyExceeded(uint256 requested, uint256 available);

    // ============================================================
    //                      CONSTRUCTOR
    // ============================================================

    /// @notice Deploy ForgeCoin with initial supply minted to deployer
    /// @param initialAdmin   Address receiving DEFAULT_ADMIN_ROLE (later transferred to Timelock)
    /// @param initialSupply  Initial tokens to mint to the admin (18 decimals)
    constructor(
        address initialAdmin,
        uint256 initialSupply
    ) ERC20("ForgeCoin", "FORGE") ERC20Permit("ForgeCoin") {
        if (initialSupply > MAX_SUPPLY) {
            revert MaxSupplyExceeded(initialSupply, MAX_SUPPLY);
        }

        _grantRole(DEFAULT_ADMIN_ROLE, initialAdmin);
        _grantRole(MINTER_ROLE, initialAdmin);

        if (initialSupply > 0) {
            _mint(initialAdmin, initialSupply);
        }
    }

    // ============================================================
    //                      MINTING
    // ============================================================

    /// @notice Mint new ForgeCoin tokens
    /// @dev Only callable by addresses with MINTER_ROLE
    /// @param to        Recipient of the minted tokens
    /// @param amount    Amount to mint (18 decimals)
    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        uint256 available = MAX_SUPPLY - totalSupply();
        if (amount > available) {
            revert MaxSupplyExceeded(amount, available);
        }
        _mint(to, amount);
    }

    // ============================================================
    //                  CONVENIENCE ROLE MANAGEMENT
    // ============================================================

    /// @notice Grant MINTER_ROLE to an address
    /// @dev Only callable by DEFAULT_ADMIN_ROLE (DAO Timelock)
    function grantMinterRole(address account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(MINTER_ROLE, account);
    }

    /// @notice Revoke MINTER_ROLE from an address
    /// @dev Only callable by DEFAULT_ADMIN_ROLE (DAO Timelock)
    function revokeMinterRole(address account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _revokeRole(MINTER_ROLE, account);
    }

    /// @notice Returns the max supply cap
    function maxSupply() external pure returns (uint256) {
        return MAX_SUPPLY;
    }

    // ============================================================
    //               REQUIRED OVERRIDES (Solidity)
    // ============================================================

    /// @dev Resolves conflict between ERC20 and ERC20Votes for _update
    function _update(
        address from,
        address to,
        uint256 value
    ) internal override(ERC20, ERC20Votes) {
        super._update(from, to, value);
    }

    /// @dev Resolves conflict between ERC20Permit and Nonces
    function nonces(
        address owner
    ) public view override(ERC20Permit, Nonces) returns (uint256) {
        return super.nonces(owner);
    }

    /// @dev ERC165 support for AccessControl
    function supportsInterface(
        bytes4 interfaceId
    ) public view override(AccessControl) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
