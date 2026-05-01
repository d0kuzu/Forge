// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IForgeVault — Interface for ERC-4626 tokenized staking vault
/// @notice Accepts ForgeCoin deposits, distributes rewards from AMM fees and Gacha revenue
interface IForgeVault {
    error ZeroShares();
    error ZeroAssets();

    event RewardsDistributed(uint256 amount, uint256 newTotalAssets);
    event FeeRecipientUpdated(address indexed newRecipient);
    event PerformanceFeeUpdated(uint256 newFeeBps);

    /// @notice Distribute rewards into the vault (increases share value)
    /// @dev Only callable by authorized contracts (AMM, Gacha)
    /// @param amount  Amount of ForgeCoin to add as rewards
    function distributeRewards(uint256 amount) external;

    /// @notice Set the performance fee recipient
    /// @dev Only callable by DAO
    function setFeeRecipient(address recipient) external;

    /// @notice Set the performance fee in basis points (max 1000 = 10%)
    /// @dev Only callable by DAO
    function setPerformanceFee(uint256 feeBps) external;

    /// @notice Get the current performance fee in bps
    function performanceFee() external view returns (uint256);

    /// @notice Get the fee recipient address
    function feeRecipient() external view returns (uint256);
}
