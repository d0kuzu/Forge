// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {DataTypes} from "../libraries/DataTypes.sol";

/// @title IForgeItems — Interface for the ForgeItems ERC1155 game items contract
/// @notice Manages game items (Dust id=0, weapons, gear) with built-in crafting mechanics
/// @dev Uses AccessControl for role-based authorization
interface IForgeItems {
    // ============================================================
    //                         ERRORS
    // ============================================================

    /// @notice Item ID has not been defined yet
    error ItemNotDefined(uint256 itemId);

    /// @notice Minting would exceed the item's max supply
    error MaxSupplyExceeded(uint256 itemId, uint256 requested, uint256 remaining);

    /// @notice Recipe ID does not exist or is inactive
    error InvalidRecipe(uint256 recipeId);

    /// @notice Caller lacks sufficient balance to craft
    error InsufficientCraftingMaterials();

    /// @notice Item is not marked as craftable
    error ItemNotCraftable(uint256 itemId);

    /// @notice Input arrays have mismatched lengths
    error ArrayLengthMismatch();

    // ============================================================
    //                         EVENTS
    // ============================================================

    /// @notice Emitted when a new item type is defined
    event ItemDefined(
        uint256 indexed itemId,
        string name,
        DataTypes.Rarity rarity,
        uint256 maxSupply,
        bool craftable
    );

    /// @notice Emitted when a crafting recipe is added
    event CraftRecipeAdded(uint256 indexed recipeId, uint256 indexed resultItemId);

    /// @notice Emitted when a crafting recipe is updated
    event CraftRecipeUpdated(uint256 indexed recipeId);

    /// @notice Emitted when a crafting recipe is deactivated
    event CraftRecipeRemoved(uint256 indexed recipeId);

    /// @notice Emitted when a player successfully crafts an item
    event ItemCrafted(
        address indexed crafter,
        uint256 indexed recipeId,
        uint256 indexed resultItemId,
        uint256 amount
    );

    // ============================================================
    //                  ITEM MANAGEMENT (DAO)
    // ============================================================

    /// @notice Define a new item type in the system
    /// @dev Only callable by GAME_ADMIN_ROLE (controlled by DAO)
    /// @param itemId       Unique ID for this item
    /// @param name         Human-readable item name
    /// @param rarity       Rarity tier (Common..Legendary)
    /// @param maxSupply    Max mintable supply (0 = unlimited)
    /// @param craftable    Whether the item can be crafted
    function defineItem(
        uint256 itemId,
        string calldata name,
        DataTypes.Rarity rarity,
        uint256 maxSupply,
        bool craftable
    ) external;

    // ============================================================
    //                 CRAFT RECIPE MANAGEMENT (DAO)
    // ============================================================

    /// @notice Add a new crafting recipe
    /// @dev Only callable by GAME_ADMIN_ROLE
    /// @param resultItemId   The item ID produced by this recipe
    /// @param inputItemIds   Required input item IDs (will be burned)
    /// @param inputAmounts   Required amounts for each input
    /// @param dustCost       Amount of Dust (id 0) consumed
    /// @param forgeCoinCost  ForgeCoin fee for crafting
    /// @return recipeId      The ID of the created recipe
    function addCraftRecipe(
        uint256 resultItemId,
        uint256[] calldata inputItemIds,
        uint256[] calldata inputAmounts,
        uint256 dustCost,
        uint256 forgeCoinCost
    ) external returns (uint256 recipeId);

    /// @notice Update an existing crafting recipe
    /// @dev Only callable by GAME_ADMIN_ROLE
    /// @param recipeId       The recipe to update
    /// @param inputItemIds   New required input item IDs
    /// @param inputAmounts   New required amounts
    /// @param dustCost       New Dust cost
    /// @param forgeCoinCost  New ForgeCoin cost
    function updateCraftRecipe(
        uint256 recipeId,
        uint256[] calldata inputItemIds,
        uint256[] calldata inputAmounts,
        uint256 dustCost,
        uint256 forgeCoinCost
    ) external;

    /// @notice Deactivate a crafting recipe
    /// @dev Only callable by GAME_ADMIN_ROLE
    /// @param recipeId    The recipe to deactivate
    function removeCraftRecipe(uint256 recipeId) external;

    // ============================================================
    //                       CRAFTING
    // ============================================================

    /// @notice Craft an item using a recipe (burns inputs, mints output)
    /// @dev Caller must have approved ForgeCoin spending and hold required items
    /// @param recipeId    The recipe to execute
    function craft(uint256 recipeId) external;

    // ============================================================
    //                  AUTHORIZED MINTING
    // ============================================================

    /// @notice Mint Dust tokens (item ID 0)
    /// @dev Only callable by MINTER_ROLE (Gacha contract)
    /// @param to        Recipient address
    /// @param amount    Amount of Dust to mint
    function mintDust(address to, uint256 amount) external;

    /// @notice Mint a specific item
    /// @dev Only callable by MINTER_ROLE (Gacha contract)
    /// @param to        Recipient address
    /// @param itemId    Item ID to mint
    /// @param amount    Amount to mint
    function mintItem(address to, uint256 itemId, uint256 amount) external;

    /// @notice Batch mint multiple items
    /// @dev Only callable by MINTER_ROLE (Gacha contract)
    /// @param to        Recipient address
    /// @param ids       Array of item IDs to mint
    /// @param amounts   Array of amounts per item
    function mintBatch(address to, uint256[] calldata ids, uint256[] calldata amounts) external;

    // ============================================================
    //                      VIEW FUNCTIONS
    // ============================================================

    /// @notice Get the full definition of an item
    /// @param itemId    The item ID to query
    /// @return definition  The ItemDefinition struct
    function getItemDefinition(uint256 itemId)
        external
        view
        returns (DataTypes.ItemDefinition memory definition);

    /// @notice Get the full details of a crafting recipe
    /// @param recipeId  The recipe ID to query
    /// @return recipe   The CraftRecipe struct
    function getCraftRecipe(uint256 recipeId)
        external
        view
        returns (DataTypes.CraftRecipe memory recipe);

    /// @notice Get the total number of recipes (including inactive)
    function getRecipeCount() external view returns (uint256);

    /// @notice Returns the GAME_ADMIN_ROLE identifier
    function GAME_ADMIN_ROLE() external view returns (bytes32);

    /// @notice Returns the MINTER_ROLE identifier
    function MINTER_ROLE() external view returns (bytes32);

    /// @notice Returns the DUST_ID constant (always 0)
    function DUST_ID() external pure returns (uint256);
}
