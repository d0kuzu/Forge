// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title DataTypes — Shared data structures for the Decentralized Forge ecosystem
/// @author Decentralized Forge Team
library DataTypes {
    // ============================================================
    //                         ENUMS
    // ============================================================

    /// @notice Item rarity tiers, determines drop weights and crafting value
    enum Rarity {
        Common,     // 0 — Dust, basic materials
        Uncommon,   // 1 — Low-tier weapons/gear
        Rare,       // 2 — Mid-tier items
        Epic,       // 3 — High-tier gear
        Legendary   // 4 — Ultra-rare, top-tier items
    }

    // ============================================================
    //                    FORGE ITEMS (ERC1155)
    // ============================================================

    /// @notice Defines metadata and constraints for a game item
    /// @param name         Human-readable item name
    /// @param rarity       Rarity tier of the item
    /// @param maxSupply    Maximum mintable supply (0 = unlimited, e.g. Dust)
    /// @param totalMinted  Running counter of minted copies
    /// @param craftable    Whether this item can be obtained via crafting
    /// @param exists       Flag to check if the item ID was defined
    struct ItemDefinition {
        string name;
        Rarity rarity;
        uint256 maxSupply;
        uint256 totalMinted;
        bool craftable;
        bool exists;
    }

    /// @notice Recipe for crafting a higher-tier item from inputs
    /// @param resultItemId   The item ID that is minted upon successful craft
    /// @param inputItemIds   Array of required input item IDs (burned)
    /// @param inputAmounts   Array of required amounts for each input item
    /// @param dustCost       Amount of Dust (item ID 0) required
    /// @param forgeCoinCost  Amount of ForgeCoin (ERC20) required as fee
    /// @param active         Whether this recipe is currently usable
    struct CraftRecipe {
        uint256 resultItemId;
        uint256[] inputItemIds;
        uint256[] inputAmounts;
        uint256 dustCost;
        uint256 forgeCoinCost;
        bool active;
    }

    // ============================================================
    //                   GACHA / LOOTBOX (VRF)
    // ============================================================

    /// @notice Configuration of a lootbox type
    /// @param priceInForgeCoin  Cost to open this lootbox in ForgeCoin
    /// @param possibleItemIds   Array of item IDs that can drop
    /// @param weights           Probability weights corresponding to each item
    /// @param totalWeight       Sum of all weights (cached for O(1) lookup)
    /// @param active            Whether this lootbox type is available
    struct LootboxConfig {
        uint256 priceInForgeCoin;
        uint256[] possibleItemIds;
        uint256[] weights;
        uint256 totalWeight;
        bool active;
    }

    /// @notice Tracks a pending VRF request for lootbox opening
    /// @param requester    Address that opened the lootbox
    /// @param lootboxType  Type of lootbox that was opened
    /// @param fulfilled    Whether the VRF callback has been received
    struct GachaRequest {
        address requester;
        uint256 lootboxType;
        bool fulfilled;
    }

    // ============================================================
    //                       AMM (DEX)
    // ============================================================

    /// @notice Snapshot of AMM pool reserves
    /// @param reserveForgeCoin  Amount of ForgeCoin in the pool
    /// @param reserveDust       Amount of Dust (ERC1155 id 0) in the pool
    /// @param blockTimestampLast Timestamp of last reserve update
    struct PoolReserves {
        uint112 reserveForgeCoin;
        uint112 reserveDust;
        uint32 blockTimestampLast;
    }

    // ============================================================
    //                   NFT RENTAL VAULT
    // ============================================================

    /// @notice A rental listing created by an item owner
    /// @param owner        Address that deposited the item
    /// @param itemId       ForgeItems ERC1155 token ID
    /// @param amount       Number of tokens listed for rent
    /// @param pricePerDay  Daily rental cost in ForgeCoin
    /// @param minDuration  Minimum rental duration in seconds
    /// @param maxDuration  Maximum rental duration in seconds
    /// @param active       Whether the listing is available
    struct RentalListing {
        address owner;
        uint256 itemId;
        uint256 amount;
        uint256 pricePerDay;
        uint256 minDuration;
        uint256 maxDuration;
        bool active;
    }

    /// @notice An active rental agreement between owner and renter
    /// @param listingId    ID of the original listing
    /// @param renter       Address renting the item
    /// @param startTime    Timestamp when the rental started
    /// @param endTime      Timestamp when the rental expires
    /// @param totalPaid    Total ForgeCoin paid for the rental
    /// @param active       Whether the rental is still active
    struct RentalAgreement {
        uint256 listingId;
        address renter;
        uint256 startTime;
        uint256 endTime;
        uint256 totalPaid;
        bool active;
    }

    // ============================================================
    //                    GUILD (Factory)
    // ============================================================

    /// @notice Configuration for a guild deployed via CREATE2
    /// @param name         Human-readable guild name
    /// @param leader       Address of the guild leader
    /// @param creationTime Timestamp of guild deployment
    struct GuildConfig {
        string name;
        address leader;
        uint256 creationTime;
    }
}
