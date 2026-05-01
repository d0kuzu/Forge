// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {ERC1155Burnable} from "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Burnable.sol";
import {ERC1155Supply} from "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Supply.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {DataTypes} from "../libraries/DataTypes.sol";

/// @title ForgeItems — ERC1155 Game Items with Crafting Mechanics
/// @notice Manages game items: Dust (id=0) and weapons/gear (id 1,2,3...).
///         Built-in crafting system: burn low-tier items + Dust → mint high-tier items.
/// @dev Uses AccessControl: GAME_ADMIN_ROLE (DAO) for item/recipe config,
///      MINTER_ROLE (GachaLootbox) for minting drops.
contract ForgeItems is ERC1155, ERC1155Burnable, ERC1155Supply, AccessControl {
    // ============================================================
    //                       CONSTANTS
    // ============================================================

    /// @notice Token ID for Dust — the base resource (unlimited supply)
    uint256 public constant DUST_ID = 0;

    /// @notice Role for game configuration (define items, manage recipes)
    bytes32 public constant GAME_ADMIN_ROLE = keccak256("GAME_ADMIN_ROLE");

    /// @notice Role for minting items (granted to GachaLootbox)
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    // ============================================================
    //                       STORAGE
    // ============================================================

    /// @notice Reference to ForgeCoin contract for crafting fees
    IERC20 public immutable forgeCoin;

    /// @notice Mapping of item ID → item definition
    mapping(uint256 => DataTypes.ItemDefinition) private _items;

    /// @notice Array of all crafting recipes
    DataTypes.CraftRecipe[] private _recipes;

    /// @notice Address that receives burned ForgeCoin from crafting (treasury/vault)
    address public craftFeeRecipient;

    // ============================================================
    //                      CUSTOM ERRORS
    // ============================================================

    error ItemNotDefined(uint256 itemId);
    error ItemAlreadyDefined(uint256 itemId);
    error MaxSupplyExceeded(uint256 itemId, uint256 requested, uint256 remaining);
    error InvalidRecipe(uint256 recipeId);
    error InsufficientCraftingMaterials(uint256 itemId, uint256 required, uint256 available);
    error ItemNotCraftable(uint256 itemId);
    error ArrayLengthMismatch();
    error ZeroAddress();

    // ============================================================
    //                         EVENTS
    // ============================================================

    event ItemDefined(
        uint256 indexed itemId,
        string name,
        DataTypes.Rarity rarity,
        uint256 maxSupply,
        bool craftable
    );

    event CraftRecipeAdded(uint256 indexed recipeId, uint256 indexed resultItemId);
    event CraftRecipeUpdated(uint256 indexed recipeId);
    event CraftRecipeRemoved(uint256 indexed recipeId);

    event ItemCrafted(
        address indexed crafter,
        uint256 indexed recipeId,
        uint256 indexed resultItemId
    );

    event CraftFeeRecipientUpdated(address indexed newRecipient);

    // ============================================================
    //                      CONSTRUCTOR
    // ============================================================

    /// @param _forgeCoin        Address of the ForgeCoin ERC20 contract
    /// @param _initialAdmin     Address receiving admin roles (later → DAO Timelock)
    /// @param _craftFeeRecipient Address receiving ForgeCoin crafting fees
    /// @param uri_              Base URI for token metadata
    constructor(
        address _forgeCoin,
        address _initialAdmin,
        address _craftFeeRecipient,
        string memory uri_
    ) ERC1155(uri_) {
        if (_forgeCoin == address(0) || _initialAdmin == address(0)) revert ZeroAddress();

        forgeCoin = IERC20(_forgeCoin);
        craftFeeRecipient = _craftFeeRecipient;

        _grantRole(DEFAULT_ADMIN_ROLE, _initialAdmin);
        _grantRole(GAME_ADMIN_ROLE, _initialAdmin);
        _grantRole(MINTER_ROLE, _initialAdmin);

        // Pre-define Dust (id 0) — unlimited supply base resource
        _items[DUST_ID] = DataTypes.ItemDefinition({
            name: "Dust",
            rarity: DataTypes.Rarity.Common,
            maxSupply: 0, // 0 = unlimited
            totalMinted: 0,
            craftable: false,
            exists: true
        });

        emit ItemDefined(DUST_ID, "Dust", DataTypes.Rarity.Common, 0, false);
    }

    // ============================================================
    //                  ITEM MANAGEMENT (DAO)
    // ============================================================

    /// @notice Define a new item type
    /// @dev Only callable by GAME_ADMIN_ROLE
    function defineItem(
        uint256 itemId,
        string calldata name,
        DataTypes.Rarity rarity,
        uint256 maxSupply,
        bool craftable
    ) external onlyRole(GAME_ADMIN_ROLE) {
        if (_items[itemId].exists) revert ItemAlreadyDefined(itemId);

        _items[itemId] = DataTypes.ItemDefinition({
            name: name,
            rarity: rarity,
            maxSupply: maxSupply,
            totalMinted: 0,
            craftable: craftable,
            exists: true
        });

        emit ItemDefined(itemId, name, rarity, maxSupply, craftable);
    }

    // ============================================================
    //                 CRAFT RECIPE MANAGEMENT (DAO)
    // ============================================================

    /// @notice Add a new crafting recipe
    /// @dev Only callable by GAME_ADMIN_ROLE
    function addCraftRecipe(
        uint256 resultItemId,
        uint256[] calldata inputItemIds,
        uint256[] calldata inputAmounts,
        uint256 dustCost,
        uint256 forgeCoinCost
    ) external onlyRole(GAME_ADMIN_ROLE) returns (uint256 recipeId) {
        if (inputItemIds.length != inputAmounts.length) revert ArrayLengthMismatch();
        if (!_items[resultItemId].exists) revert ItemNotDefined(resultItemId);
        if (!_items[resultItemId].craftable) revert ItemNotCraftable(resultItemId);

        // Validate all input items exist
        for (uint256 i = 0; i < inputItemIds.length; i++) {
            if (!_items[inputItemIds[i]].exists) revert ItemNotDefined(inputItemIds[i]);
        }

        recipeId = _recipes.length;
        _recipes.push(DataTypes.CraftRecipe({
            resultItemId: resultItemId,
            inputItemIds: inputItemIds,
            inputAmounts: inputAmounts,
            dustCost: dustCost,
            forgeCoinCost: forgeCoinCost,
            active: true
        }));

        emit CraftRecipeAdded(recipeId, resultItemId);
    }

    /// @notice Update an existing crafting recipe
    function updateCraftRecipe(
        uint256 recipeId,
        uint256[] calldata inputItemIds,
        uint256[] calldata inputAmounts,
        uint256 dustCost,
        uint256 forgeCoinCost
    ) external onlyRole(GAME_ADMIN_ROLE) {
        if (recipeId >= _recipes.length || !_recipes[recipeId].active) {
            revert InvalidRecipe(recipeId);
        }
        if (inputItemIds.length != inputAmounts.length) revert ArrayLengthMismatch();

        DataTypes.CraftRecipe storage recipe = _recipes[recipeId];
        recipe.inputItemIds = inputItemIds;
        recipe.inputAmounts = inputAmounts;
        recipe.dustCost = dustCost;
        recipe.forgeCoinCost = forgeCoinCost;

        emit CraftRecipeUpdated(recipeId);
    }

    /// @notice Deactivate a crafting recipe
    function removeCraftRecipe(uint256 recipeId) external onlyRole(GAME_ADMIN_ROLE) {
        if (recipeId >= _recipes.length || !_recipes[recipeId].active) {
            revert InvalidRecipe(recipeId);
        }
        _recipes[recipeId].active = false;
        emit CraftRecipeRemoved(recipeId);
    }

    // ============================================================
    //                       CRAFTING
    // ============================================================

    /// @notice Craft an item using a recipe
    /// @dev Burns all input items + Dust, transfers ForgeCoin fee, mints result
    /// @param recipeId  The recipe to execute
    function craft(uint256 recipeId) external {
        if (recipeId >= _recipes.length || !_recipes[recipeId].active) {
            revert InvalidRecipe(recipeId);
        }

        DataTypes.CraftRecipe storage recipe = _recipes[recipeId];
        address crafter = msg.sender;

        // 1. Check & burn Dust cost
        if (recipe.dustCost > 0) {
            uint256 dustBalance = balanceOf(crafter, DUST_ID);
            if (dustBalance < recipe.dustCost) {
                revert InsufficientCraftingMaterials(DUST_ID, recipe.dustCost, dustBalance);
            }
            _burn(crafter, DUST_ID, recipe.dustCost);
        }

        // 2. Check & burn input items
        uint256 inputLen = recipe.inputItemIds.length;
        for (uint256 i = 0; i < inputLen; i++) {
            uint256 itemId = recipe.inputItemIds[i];
            uint256 required = recipe.inputAmounts[i];
            uint256 available = balanceOf(crafter, itemId);
            if (available < required) {
                revert InsufficientCraftingMaterials(itemId, required, available);
            }
            _burn(crafter, itemId, required);
        }

        // 3. Transfer ForgeCoin fee to craft fee recipient
        if (recipe.forgeCoinCost > 0) {
            bool success = forgeCoin.transferFrom(crafter, craftFeeRecipient, recipe.forgeCoinCost);
            require(success, "ForgeCoin transfer failed");
        }

        // 4. Mint result item (respecting max supply)
        uint256 resultId = recipe.resultItemId;
        DataTypes.ItemDefinition storage resultItem = _items[resultId];
        if (resultItem.maxSupply > 0) {
            uint256 remaining = resultItem.maxSupply - resultItem.totalMinted;
            if (remaining == 0) {
                revert MaxSupplyExceeded(resultId, 1, 0);
            }
        }
        resultItem.totalMinted += 1;
        _mint(crafter, resultId, 1, "");

        emit ItemCrafted(crafter, recipeId, resultId);
    }

    // ============================================================
    //                  AUTHORIZED MINTING
    // ============================================================

    /// @notice Mint Dust tokens (item ID 0)
    /// @dev Only callable by MINTER_ROLE (GachaLootbox)
    function mintDust(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        _items[DUST_ID].totalMinted += amount;
        _mint(to, DUST_ID, amount, "");
    }

    /// @notice Mint a specific item
    /// @dev Only callable by MINTER_ROLE (GachaLootbox)
    function mintItem(address to, uint256 itemId, uint256 amount) external onlyRole(MINTER_ROLE) {
        if (!_items[itemId].exists) revert ItemNotDefined(itemId);

        DataTypes.ItemDefinition storage item = _items[itemId];
        if (item.maxSupply > 0) {
            uint256 remaining = item.maxSupply - item.totalMinted;
            if (amount > remaining) {
                revert MaxSupplyExceeded(itemId, amount, remaining);
            }
        }

        item.totalMinted += amount;
        _mint(to, itemId, amount, "");
    }

    /// @notice Batch mint multiple items
    /// @dev Only callable by MINTER_ROLE (GachaLootbox)
    function mintBatch(
        address to,
        uint256[] calldata ids,
        uint256[] calldata amounts
    ) external onlyRole(MINTER_ROLE) {
        if (ids.length != amounts.length) revert ArrayLengthMismatch();

        for (uint256 i = 0; i < ids.length; i++) {
            if (!_items[ids[i]].exists) revert ItemNotDefined(ids[i]);

            DataTypes.ItemDefinition storage item = _items[ids[i]];
            if (item.maxSupply > 0) {
                uint256 remaining = item.maxSupply - item.totalMinted;
                if (amounts[i] > remaining) {
                    revert MaxSupplyExceeded(ids[i], amounts[i], remaining);
                }
            }
            item.totalMinted += amounts[i];
        }

        _mintBatch(to, ids, amounts, "");
    }

    // ============================================================
    //                    ADMIN SETTERS
    // ============================================================

    /// @notice Update the craft fee recipient address
    function setCraftFeeRecipient(address newRecipient) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newRecipient == address(0)) revert ZeroAddress();
        craftFeeRecipient = newRecipient;
        emit CraftFeeRecipientUpdated(newRecipient);
    }

    /// @notice Update the base URI for metadata
    function setURI(string calldata newURI) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setURI(newURI);
    }

    // ============================================================
    //                      VIEW FUNCTIONS
    // ============================================================

    /// @notice Get the full definition of an item
    function getItemDefinition(uint256 itemId)
        external
        view
        returns (DataTypes.ItemDefinition memory)
    {
        if (!_items[itemId].exists) revert ItemNotDefined(itemId);
        return _items[itemId];
    }

    /// @notice Get the full details of a crafting recipe
    function getCraftRecipe(uint256 recipeId)
        external
        view
        returns (DataTypes.CraftRecipe memory)
    {
        if (recipeId >= _recipes.length) revert InvalidRecipe(recipeId);
        return _recipes[recipeId];
    }

    /// @notice Get the total number of recipes (including inactive)
    function getRecipeCount() external view returns (uint256) {
        return _recipes.length;
    }

    // ============================================================
    //               REQUIRED OVERRIDES (Solidity)
    // ============================================================

    /// @dev Resolves conflict between ERC1155 and ERC1155Supply
    function _update(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory values
    ) internal override(ERC1155, ERC1155Supply) {
        super._update(from, to, ids, values);
    }

    /// @dev ERC165 support
    function supportsInterface(
        bytes4 interfaceId
    ) public view override(ERC1155, AccessControl) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
