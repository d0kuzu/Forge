// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title ForgeLPToken — Liquidity Provider Token for ForgeAMM
/// @notice ERC20 token representing shares in the ForgeCoin/Dust liquidity pool.
///         Only the AMM contract can mint and burn LP tokens.
/// @dev Minimal ERC20 with restricted mint/burn, deployed by the AMM constructor.
contract ForgeLPToken is ERC20 {
    /// @notice The AMM contract that controls minting and burning
    address public immutable amm;

    /// @notice Caller is not the authorized AMM contract
    error OnlyAMM();

    modifier onlyAMM() {
        if (msg.sender != amm) revert OnlyAMM();
        _;
    }

    /// @param _amm  The ForgeAMM contract address (sole minter/burner)
    constructor(address _amm) ERC20("Forge LP Token", "FORGE-LP") {
        amm = _amm;
    }

    /// @notice Mint LP tokens to a liquidity provider
    /// @dev Only callable by the AMM contract
    function mint(address to, uint256 amount) external onlyAMM {
        _mint(to, amount);
    }

    /// @notice Burn LP tokens from a liquidity provider
    /// @dev Only callable by the AMM contract
    function burn(address from, uint256 amount) external onlyAMM {
        _burn(from, amount);
    }
}
