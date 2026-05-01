// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @title ForgeVault — ERC-4626 Tokenized Staking Vault
/// @notice Accepts ForgeCoin deposits and distributes rewards from AMM fees
///         and Gacha lootbox revenue. Share value increases over time as
///         rewards accrue, creating passive yield for stakers.
/// @dev Extends OZ ERC4626 with:
///      - DISTRIBUTOR_ROLE: authorized reward sources (AMM, Gacha)
///      - Performance fee: configurable % taken on reward distribution
///      - AccessControl: DAO manages roles and fee parameters
contract ForgeVault is ERC4626, AccessControl {
    using SafeERC20 for IERC20;
    using Math for uint256;

    // ============================================================
    //                       CONSTANTS
    // ============================================================

    /// @notice Role for contracts authorized to distribute rewards
    bytes32 public constant DISTRIBUTOR_ROLE = keccak256("DISTRIBUTOR_ROLE");

    /// @notice Maximum performance fee: 10% (1000 basis points)
    uint256 public constant MAX_PERFORMANCE_FEE = 1000;

    /// @notice Basis points denominator
    uint256 public constant BPS_DENOMINATOR = 10_000;

    // ============================================================
    //                       STORAGE
    // ============================================================

    /// @notice Performance fee in basis points (e.g., 500 = 5%)
    uint256 public performanceFee;

    /// @notice Address receiving performance fees
    address public feeRecipient;

    /// @notice Total rewards distributed lifetime
    uint256 public totalRewardsDistributed;

    // ============================================================
    //                      CUSTOM ERRORS
    // ============================================================

    error ZeroAddress();
    error FeeTooHigh(uint256 requested, uint256 maximum);
    error ZeroAmount();

    // ============================================================
    //                         EVENTS
    // ============================================================

    event RewardsDistributed(uint256 amount, uint256 feeAmount, uint256 newTotalAssets);
    event PerformanceFeeUpdated(uint256 oldFee, uint256 newFee);
    event FeeRecipientUpdated(address indexed oldRecipient, address indexed newRecipient);

    // ============================================================
    //                      CONSTRUCTOR
    // ============================================================

    /// @param _forgeCoin      ForgeCoin ERC20 address (the vault's underlying asset)
    /// @param _admin          Initial admin (later transferred to DAO Timelock)
    /// @param _feeRecipient   Address receiving performance fees
    /// @param _performanceFee Initial performance fee in basis points
    constructor(
        IERC20 _forgeCoin,
        address _admin,
        address _feeRecipient,
        uint256 _performanceFee
    )
        ERC4626(_forgeCoin)
        ERC20("Staked ForgeCoin", "sFORGE")
    {
        if (_admin == address(0)) revert ZeroAddress();
        if (_performanceFee > MAX_PERFORMANCE_FEE) {
            revert FeeTooHigh(_performanceFee, MAX_PERFORMANCE_FEE);
        }

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(DISTRIBUTOR_ROLE, _admin);

        feeRecipient = _feeRecipient;
        performanceFee = _performanceFee;
    }

    // ============================================================
    //                   REWARD DISTRIBUTION
    // ============================================================

    /// @notice Distribute rewards into the vault (increases share value)
    /// @dev Only callable by authorized contracts (AMM, Gacha).
    ///      Transfers ForgeCoin from caller into vault. A performance fee
    ///      is taken and sent to feeRecipient; the rest accrues to stakers.
    /// @param amount  Total ForgeCoin to distribute as rewards
    function distributeRewards(uint256 amount) external onlyRole(DISTRIBUTOR_ROLE) {
        if (amount == 0) revert ZeroAmount();

        IERC20 asset_ = IERC20(asset());

        // Calculate and extract performance fee
        uint256 feeAmount = 0;
        if (performanceFee > 0 && feeRecipient != address(0)) {
            feeAmount = amount.mulDiv(performanceFee, BPS_DENOMINATOR);
            if (feeAmount > 0) {
                asset_.safeTransferFrom(msg.sender, feeRecipient, feeAmount);
            }
        }

        // Transfer remaining rewards into the vault
        uint256 rewardAmount = amount - feeAmount;
        if (rewardAmount > 0) {
            asset_.safeTransferFrom(msg.sender, address(this), rewardAmount);
        }

        totalRewardsDistributed += amount;

        emit RewardsDistributed(amount, feeAmount, totalAssets());
    }

    // ============================================================
    //                    ADMIN FUNCTIONS (DAO)
    // ============================================================

    /// @notice Set the performance fee
    /// @dev Only callable by DEFAULT_ADMIN_ROLE (DAO Timelock)
    /// @param newFee  New fee in basis points (max 1000 = 10%)
    function setPerformanceFee(uint256 newFee) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newFee > MAX_PERFORMANCE_FEE) revert FeeTooHigh(newFee, MAX_PERFORMANCE_FEE);

        uint256 oldFee = performanceFee;
        performanceFee = newFee;

        emit PerformanceFeeUpdated(oldFee, newFee);
    }

    /// @notice Set the fee recipient address
    /// @dev Only callable by DEFAULT_ADMIN_ROLE (DAO Timelock)
    function setFeeRecipient(address newRecipient) external onlyRole(DEFAULT_ADMIN_ROLE) {
        address oldRecipient = feeRecipient;
        feeRecipient = newRecipient;

        emit FeeRecipientUpdated(oldRecipient, newRecipient);
    }

    // ============================================================
    //               REQUIRED OVERRIDES (Solidity)
    // ============================================================

    /// @dev Resolve conflict between ERC20 and AccessControl
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    /// @dev Override decimals to match underlying asset
    function decimals() public view override(ERC4626) returns (uint8) {
        return super.decimals();
    }
}
