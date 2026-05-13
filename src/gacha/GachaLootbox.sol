// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlUpgradeable} from
    "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {PausableUpgradeable} from
    "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {VRFConsumerBaseV2Plus} from "../chainlink/VRFConsumerBaseV2Plus.sol";
import {IVRFCoordinatorV2Plus} from "../chainlink/IVRFCoordinatorV2Plus.sol";
import {VRFV2PlusClient} from "../chainlink/VRFV2PlusClient.sol";
import {DataTypes} from "../libraries/DataTypes.sol";
import {IForgeVault} from "../interfaces/IForgeVault.sol";

/// @notice Interface for ForgeItems minting (avoids circular dependency)
interface IForgeItemsMinter {
    function mintDust(address to, uint256 amount) external;
    function mintItem(address to, uint256 itemId, uint256 amount) external;
}

/// @title GachaLootbox — Provably Fair Lootbox System
/// @notice Accepts ForgeCoin payment and uses Chainlink VRF v2.5 for random item drops.
///         Deployed behind a UUPS Proxy (ERC1967) for upgradeability.
/// @dev Architecture:
///      - UUPS Proxy: upgrade logic controlled by DEFAULT_ADMIN_ROLE (DAO Timelock)
///      - VRF v2.5: provably fair randomness via Chainlink
///      - AccessControl: GAME_ADMIN_ROLE for config, TREASURY_ROLE for revenue
///      - Pausable: emergency stop capability
///      - ReentrancyGuard: protection on all state-changing external calls
contract GachaLootbox is
    Initializable,
    UUPSUpgradeable,
    AccessControlUpgradeable,
    ReentrancyGuard,
    PausableUpgradeable,
    VRFConsumerBaseV2Plus
{
    using SafeERC20 for IERC20;

    // ============================================================
    //                       CONSTANTS
    // ============================================================

    bytes32 public constant GAME_ADMIN_ROLE = keccak256("GAME_ADMIN_ROLE");
    bytes32 public constant TREASURY_ROLE = keccak256("TREASURY_ROLE");

    /// @notice Version tag for upgrade tracking
    uint256 public constant VERSION = 1;

    // ============================================================
    //                    STORAGE (upgradeable-safe)
    // ============================================================

    /// @notice ForgeCoin token used for lootbox payments
    IERC20 public forgeCoin;

    /// @notice ForgeItems contract for minting drops
    IForgeItemsMinter public forgeItems;

    /// @notice Chainlink VRF subscription ID
    uint256 public s_subscriptionId;

    /// @notice Chainlink VRF key hash (gas lane)
    bytes32 public s_keyHash;

    /// @notice Gas limit for VRF callback
    uint32 public s_callbackGasLimit;

    /// @notice Block confirmations before VRF callback
    uint16 public s_requestConfirmations;

    /// @notice Number of random words per request (always 1)
    uint32 public constant NUM_WORDS = 1;

    /// @notice Lootbox type => configuration
    mapping(uint256 => DataTypes.LootboxConfig) private _lootboxConfigs;

    /// @notice VRF request ID => request details
    mapping(uint256 => DataTypes.GachaRequest) private _requests;

    /// @notice Total ForgeCoin revenue accumulated
    uint256 public totalRevenue;

    /// @notice Dust amount awarded when Dust is the drop result
    uint256 public dustDropAmount;

    /// @notice Vault for sweeping revenue
    IForgeVault public forgeVault;

    /// @dev Gap for future storage variables in upgrades
    uint256[39] private __gap;

    // ============================================================
    //                      CUSTOM ERRORS
    // ============================================================

    error LootboxNotActive(uint256 lootboxType);
    error InsufficientPayment();
    error RequestNotFound(uint256 requestId);
    error RequestAlreadyFulfilled(uint256 requestId);
    error ArrayLengthMismatch();
    error InvalidWeights();
    error ZeroAddress();
    error InsufficientRevenue(uint256 requested, uint256 available);

    // ============================================================
    //                         EVENTS
    // ============================================================

    event LootboxConfigured(uint256 indexed lootboxType, uint256 price, uint256 itemCount);
    event LootboxOpened(uint256 indexed requestId, address indexed requester, uint256 indexed lootboxType);
    event LootboxFulfilled(uint256 indexed requestId, address indexed requester, uint256 itemId, uint256 amount);
    event DropRatesUpdated(uint256 indexed lootboxType);
    event PriceUpdated(uint256 indexed lootboxType, uint256 oldPrice, uint256 newPrice);
    event RevenueWithdrawn(address indexed to, uint256 amount);
    event VRFConfigUpdated(uint256 subId, bytes32 keyHash, uint32 callbackGasLimit, uint16 requestConfirmations);
    event DustDropAmountUpdated(uint256 oldAmount, uint256 newAmount);

    // ============================================================
    //                      INITIALIZER
    // ============================================================

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initialize the GachaLootbox (called once via proxy)
    /// @param _admin               Admin address (later transferred to DAO Timelock)
    /// @param _forgeCoin           ForgeCoin ERC20 address
    /// @param _forgeItems          ForgeItems ERC1155 address
    /// @param _vrfCoordinator      Chainlink VRF Coordinator address
    /// @param _subscriptionId      VRF subscription ID
    /// @param _keyHash             VRF gas lane key hash
    /// @param _callbackGasLimit    Gas limit for VRF callback
    /// @param _requestConfirmations Block confirmations before callback
    /// @param _dustDropAmount      Amount of Dust to mint when Dust drops
    function initialize(
        address _admin,
        address _forgeCoin,
        address _forgeItems,
        address _vrfCoordinator,
        uint256 _subscriptionId,
        bytes32 _keyHash,
        uint32 _callbackGasLimit,
        uint16 _requestConfirmations,
        uint256 _dustDropAmount
    ) external initializer {
        if (_admin == address(0) || _forgeCoin == address(0) || _forgeItems == address(0) || _vrfCoordinator == address(0)) {
            revert ZeroAddress();
        }

        __AccessControl_init();
        __Pausable_init();
        _setVRFCoordinator(_vrfCoordinator);

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(GAME_ADMIN_ROLE, _admin);
        _grantRole(TREASURY_ROLE, _admin);

        forgeCoin = IERC20(_forgeCoin);
        forgeItems = IForgeItemsMinter(_forgeItems);

        s_subscriptionId = _subscriptionId;
        s_keyHash = _keyHash;
        s_callbackGasLimit = _callbackGasLimit;
        s_requestConfirmations = _requestConfirmations;
        dustDropAmount = _dustDropAmount;
    }

    // ============================================================
    //                  LOOTBOX CONFIGURATION (DAO)
    // ============================================================

    /// @notice Configure a new lootbox type or update an existing one
    /// @dev Only callable by GAME_ADMIN_ROLE (DAO Timelock)
    /// @param lootboxType   Unique type identifier
    /// @param price         Price in ForgeCoin to open
    /// @param itemIds       Array of possible item IDs that can drop
    /// @param weights       Probability weights for each item (higher = more likely)
    function configureLootbox(
        uint256 lootboxType,
        uint256 price,
        uint256[] calldata itemIds,
        uint256[] calldata weights
    ) external onlyRole(GAME_ADMIN_ROLE) {
        if (itemIds.length != weights.length) revert ArrayLengthMismatch();
        if (itemIds.length == 0) revert ArrayLengthMismatch();

        uint256 total = 0;
        for (uint256 i = 0; i < weights.length; i++) {
            total += weights[i];
        }
        if (total == 0) revert InvalidWeights();

        _lootboxConfigs[lootboxType] = DataTypes.LootboxConfig({
            priceInForgeCoin: price,
            possibleItemIds: itemIds,
            weights: weights,
            totalWeight: total,
            active: true
        });

        emit LootboxConfigured(lootboxType, price, itemIds.length);
    }

    /// @notice Update drop rates (probability weights) for an existing lootbox
    /// @dev Only callable by GAME_ADMIN_ROLE (DAO Timelock)
    function updateDropRates(
        uint256 lootboxType,
        uint256[] calldata newWeights
    ) external onlyRole(GAME_ADMIN_ROLE) {
        DataTypes.LootboxConfig storage config = _lootboxConfigs[lootboxType];
        if (!config.active) revert LootboxNotActive(lootboxType);
        if (newWeights.length != config.possibleItemIds.length) revert ArrayLengthMismatch();

        uint256 total = 0;
        for (uint256 i = 0; i < newWeights.length; i++) {
            total += newWeights[i];
        }
        if (total == 0) revert InvalidWeights();

        config.weights = newWeights;
        config.totalWeight = total;

        emit DropRatesUpdated(lootboxType);
    }

    /// @notice Update lootbox price
    /// @dev Only callable by GAME_ADMIN_ROLE (DAO Timelock)
    function setPrice(
        uint256 lootboxType,
        uint256 newPrice
    ) external onlyRole(GAME_ADMIN_ROLE) {
        DataTypes.LootboxConfig storage config = _lootboxConfigs[lootboxType];
        if (!config.active) revert LootboxNotActive(lootboxType);

        uint256 oldPrice = config.priceInForgeCoin;
        config.priceInForgeCoin = newPrice;

        emit PriceUpdated(lootboxType, oldPrice, newPrice);
    }

    // ============================================================
    //                      USER ACTIONS
    // ============================================================

    /// @notice Open a lootbox by paying ForgeCoin
    /// @dev Transfers ForgeCoin from caller, sends VRF request
    /// @param lootboxType   The type of lootbox to open
    /// @return requestId    The Chainlink VRF request ID
    function openLootbox(uint256 lootboxType)
        external
        nonReentrant
        whenNotPaused
        returns (uint256 requestId)
    {
        DataTypes.LootboxConfig storage config = _lootboxConfigs[lootboxType];
        if (!config.active) revert LootboxNotActive(lootboxType);

        // Transfer payment
        uint256 price = config.priceInForgeCoin;
        forgeCoin.safeTransferFrom(msg.sender, address(this), price);
        totalRevenue += price;

        // Immediately route revenue to ForgeVault if configured
        if (address(forgeVault) != address(0)) {
            forgeCoin.approve(address(forgeVault), price);
            forgeVault.distributeRewards(price);
        }

        // Request VRF random number
        requestId = s_vrfCoordinator.requestRandomWords(
            VRFV2PlusClient.RandomWordsRequest({
                keyHash: s_keyHash,
                subId: s_subscriptionId,
                requestConfirmations: s_requestConfirmations,
                callbackGasLimit: s_callbackGasLimit,
                numWords: NUM_WORDS,
                extraArgs: VRFV2PlusClient._argsToBytes(false) // pay with LINK
            })
        );

        // Store request
        _requests[requestId] = DataTypes.GachaRequest({
            requester: msg.sender,
            lootboxType: lootboxType,
            fulfilled: false
        });

        emit LootboxOpened(requestId, msg.sender, lootboxType);
    }

    // ============================================================
    //                    VRF CALLBACK
    // ============================================================

    /// @notice Called by VRF Coordinator with random result
    /// @dev Determines the drop item based on weighted random selection
    /// @param requestId    The VRF request ID
    /// @param randomWords  Array containing one random uint256
    function fulfillRandomWords(
        uint256 requestId,
        uint256[] calldata randomWords
    ) internal override {
        DataTypes.GachaRequest storage request = _requests[requestId];
        if (request.requester == address(0)) revert RequestNotFound(requestId);
        if (request.fulfilled) revert RequestAlreadyFulfilled(requestId);

        request.fulfilled = true;

        DataTypes.LootboxConfig storage config = _lootboxConfigs[request.lootboxType];

        // Weighted random selection
        uint256 randomValue = randomWords[0] % config.totalWeight;
        uint256 cumulativeWeight = 0;
        uint256 selectedItemId;

        for (uint256 i = 0; i < config.weights.length; i++) {
            cumulativeWeight += config.weights[i];
            if (randomValue < cumulativeWeight) {
                selectedItemId = config.possibleItemIds[i];
                break;
            }
        }

        // Mint the item to the requester
        address requester = request.requester;
        uint256 mintAmount;

        if (selectedItemId == 0) {
            // Item ID 0 = Dust — mint bulk amount
            mintAmount = dustDropAmount;
            forgeItems.mintDust(requester, mintAmount);
        } else {
            // NFT item — mint 1 copy
            mintAmount = 1;
            forgeItems.mintItem(requester, selectedItemId, mintAmount);
        }

        emit LootboxFulfilled(requestId, requester, selectedItemId, mintAmount);
    }

    // ============================================================
    //                    REVENUE MANAGEMENT
    // ============================================================

    /// @notice Withdraw accumulated ForgeCoin revenue
    /// @dev Only callable by TREASURY_ROLE
    /// @param to        Recipient (typically ForgeVault)
    /// @param amount    Amount to withdraw
    function withdrawRevenue(
        address to,
        uint256 amount
    ) external onlyRole(TREASURY_ROLE) nonReentrant {
        if (to == address(0)) revert ZeroAddress();
        uint256 balance = forgeCoin.balanceOf(address(this));
        if (amount > balance) revert InsufficientRevenue(amount, balance);

        forgeCoin.safeTransfer(to, amount);
        emit RevenueWithdrawn(to, amount);
    }

    /// @notice Sweep all accumulated ForgeCoin revenue directly to the Vault
    /// @dev Only needed if forgeVault was set after some revenue had already accumulated
    function sweepRevenue() external nonReentrant {
        if (address(forgeVault) == address(0)) revert ZeroAddress();
        uint256 balance = forgeCoin.balanceOf(address(this));
        if (balance == 0) revert InsufficientRevenue(1, 0);

        forgeCoin.approve(address(forgeVault), balance);
        forgeVault.distributeRewards(balance);
        emit RevenueWithdrawn(address(forgeVault), balance);
    }

    // ============================================================
    //                    ADMIN FUNCTIONS
    // ============================================================

    /// @notice Update Chainlink VRF configuration
    function updateVRFConfig(
        uint256 subId,
        bytes32 keyHash,
        uint32 callbackGasLimit,
        uint16 requestConfirmations
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        s_subscriptionId = subId;
        s_keyHash = keyHash;
        s_callbackGasLimit = callbackGasLimit;
        s_requestConfirmations = requestConfirmations;

        emit VRFConfigUpdated(subId, keyHash, callbackGasLimit, requestConfirmations);
    }

    /// @notice Update the Dust drop amount
    function setDustDropAmount(uint256 newAmount) external onlyRole(GAME_ADMIN_ROLE) {
        uint256 old = dustDropAmount;
        dustDropAmount = newAmount;
        emit DustDropAmountUpdated(old, newAmount);
    }

    /// @notice Update the VRF Coordinator address
    function setVRFCoordinator(address coordinator) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (coordinator == address(0)) revert ZeroAddress();
        _setVRFCoordinator(coordinator);
    }

    /// @notice Set the ForgeVault address for sweeping revenue
    function setForgeVault(address _vault) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_vault == address(0)) revert ZeroAddress();
        forgeVault = IForgeVault(_vault);
    }

    /// @notice Pause the contract (emergency)
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    /// @notice Unpause the contract
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    // ============================================================
    //                      VIEW FUNCTIONS
    // ============================================================

    /// @notice Get full configuration of a lootbox type
    function getLootboxConfig(uint256 lootboxType)
        external
        view
        returns (DataTypes.LootboxConfig memory)
    {
        return _lootboxConfigs[lootboxType];
    }

    /// @notice Get details of a VRF request
    function getRequest(uint256 requestId)
        external
        view
        returns (DataTypes.GachaRequest memory)
    {
        return _requests[requestId];
    }

    // ============================================================
    //                    UUPS UPGRADE AUTH
    // ============================================================

    /// @notice Authorize an upgrade to a new implementation
    /// @dev Only callable by DEFAULT_ADMIN_ROLE (DAO Timelock)
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}
}
