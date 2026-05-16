// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {ForgeCoin} from "../src/tokens/ForgeCoin.sol";
import {ForgeItems} from "../src/tokens/ForgeItems.sol";
import {DataTypes} from "../src/libraries/DataTypes.sol";

contract ForgeItemsTest is Test {
    ForgeCoin public coin;
    ForgeItems public items;

    address public admin = address(this);
    address public treasury = address(0x999);
    address public alice = address(0x1111);
    address public bob = address(0x2222);

    uint256 constant DUST_ID = 0;
    uint256 constant SWORD_ID = 1;
    uint256 constant SHIELD_ID = 2;
    uint256 constant EPIC_SWORD_ID = 3;
    uint256 constant NON_CRAFTABLE_ID = 4;

    function setUp() public {
        coin = new ForgeCoin(admin, 1_000_000 * 10**18);
        items = new ForgeItems(address(coin), admin, treasury);
        items.setURI("https://api.forge.com/items/");

        coin.transfer(alice, 1000 * 10**18);
        coin.transfer(bob, 1000 * 10**18);
        items.mintDust(alice, 500);

        // Define Items
        items.defineItem(SWORD_ID, "Basic Sword", DataTypes.Rarity.Common, 0, true);
        items.defineItem(SHIELD_ID, "Basic Shield", DataTypes.Rarity.Common, 0, true);
        items.defineItem(EPIC_SWORD_ID, "Epic Sword", DataTypes.Rarity.Epic, 100, true); 
        items.defineItem(NON_CRAFTABLE_ID, "Golden Dust", DataTypes.Rarity.Rare, 0, false); 
    }

    // --- Unit Tests ---

    function test_DefineItem() public {
        DataTypes.ItemDefinition memory def = items.getItemDefinition(SWORD_ID);
        assertEq(def.name, "Basic Sword");
        assertEq(uint8(def.rarity), uint8(DataTypes.Rarity.Common));
        assertTrue(def.craftable);
    }

    function test_RevertIfItemAlreadyDefined() public {
        vm.expectRevert(abi.encodeWithSelector(ForgeItems.ItemAlreadyDefined.selector, SWORD_ID));
        items.defineItem(SWORD_ID, "Another Sword", DataTypes.Rarity.Common, 0, true);
    }

    function test_RevertIfItemNotDefined() public {
        vm.expectRevert(abi.encodeWithSelector(ForgeItems.ItemNotDefined.selector, 999));
        items.getItemDefinition(999);
    }

    function test_AddCraftRecipeArrayMismatch() public {
        uint256[] memory inputIds = new uint256[](1);
        inputIds[0] = SWORD_ID;
        uint256[] memory inputAmts = new uint256[](0);

        vm.expectRevert(ForgeItems.ArrayLengthMismatch.selector);
        items.addCraftRecipe(EPIC_SWORD_ID, inputIds, inputAmts, 0, 0);
    }

    function test_AddCraftRecipeNotCraftable() public {
        uint256[] memory inputIds = new uint256[](1);
        inputIds[0] = SWORD_ID;
        uint256[] memory inputAmts = new uint256[](1);
        inputAmts[0] = 1;

        vm.expectRevert(abi.encodeWithSelector(ForgeItems.ItemNotCraftable.selector, NON_CRAFTABLE_ID));
        items.addCraftRecipe(NON_CRAFTABLE_ID, inputIds, inputAmts, 0, 0);
    }

    function test_AddCraftRecipeInputNotDefined() public {
        uint256[] memory inputIds = new uint256[](1);
        inputIds[0] = 999;
        uint256[] memory inputAmts = new uint256[](1);
        inputAmts[0] = 1;

        vm.expectRevert(abi.encodeWithSelector(ForgeItems.ItemNotDefined.selector, 999));
        items.addCraftRecipe(EPIC_SWORD_ID, inputIds, inputAmts, 0, 0);
    }

    function test_AddAndCraftRecipe() public {
        items.mintItem(alice, SWORD_ID, 2);
        
        uint256[] memory inputIds = new uint256[](1);
        inputIds[0] = SWORD_ID;
        
        uint256[] memory inputAmts = new uint256[](1);
        inputAmts[0] = 2;

        uint256 recipeId = items.addCraftRecipe(EPIC_SWORD_ID, inputIds, inputAmts, 100, 50 * 10**18);

        vm.startPrank(alice);
        coin.approve(address(items), 50 * 10**18);
        
        uint256 aliceCoinBefore = coin.balanceOf(alice);
        uint256 aliceDustBefore = items.balanceOf(alice, DUST_ID);
        
        items.craft(recipeId);
        vm.stopPrank();

        assertEq(items.balanceOf(alice, EPIC_SWORD_ID), 1);
        assertEq(items.balanceOf(alice, SWORD_ID), 0);
        assertEq(items.balanceOf(alice, DUST_ID), aliceDustBefore - 100);
        assertEq(coin.balanceOf(alice), aliceCoinBefore - 50 * 10**18);
        assertEq(coin.balanceOf(treasury), 50 * 10**18);
    }

    function test_UpdateCraftRecipe() public {
        uint256[] memory inputIds = new uint256[](1);
        inputIds[0] = SWORD_ID;
        uint256[] memory inputAmts = new uint256[](1);
        inputAmts[0] = 2;

        uint256 recipeId = items.addCraftRecipe(EPIC_SWORD_ID, inputIds, inputAmts, 100, 50 * 10**18);

        inputAmts[0] = 3; // Update to 3 swords
        items.updateCraftRecipe(recipeId, inputIds, inputAmts, 50, 20 * 10**18);

        DataTypes.CraftRecipe memory r = items.getCraftRecipe(recipeId);
        assertEq(r.inputAmounts[0], 3);
        assertEq(r.dustCost, 50);
        assertEq(r.forgeCoinCost, 20 * 10**18);
    }

    function test_UpdateCraftRecipeReverts() public {
        uint256[] memory inputIds = new uint256[](1);
        inputIds[0] = SWORD_ID;
        uint256[] memory inputAmts = new uint256[](1);
        inputAmts[0] = 2;

        vm.expectRevert(abi.encodeWithSelector(ForgeItems.InvalidRecipe.selector, 99));
        items.updateCraftRecipe(99, inputIds, inputAmts, 0, 0);
    }

    function test_RemoveCraftRecipe() public {
        uint256[] memory inputIds = new uint256[](1);
        inputIds[0] = SWORD_ID;
        uint256[] memory inputAmts = new uint256[](1);
        inputAmts[0] = 2;

        uint256 recipeId = items.addCraftRecipe(EPIC_SWORD_ID, inputIds, inputAmts, 0, 0);
        items.removeCraftRecipe(recipeId);

        vm.expectRevert(abi.encodeWithSelector(ForgeItems.InvalidRecipe.selector, recipeId));
        items.craft(recipeId);
    }

    function test_RevertCraftIfInsufficientMaterials() public {
        uint256[] memory inputIds = new uint256[](1);
        inputIds[0] = SWORD_ID;
        uint256[] memory inputAmts = new uint256[](1);
        inputAmts[0] = 5;

        uint256 recipeId = items.addCraftRecipe(EPIC_SWORD_ID, inputIds, inputAmts, 0, 0);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(ForgeItems.InsufficientCraftingMaterials.selector, SWORD_ID, 5, 0));
        items.craft(recipeId);
    }

    function test_MaxSupplyEnforcement() public {
        items.mintItem(alice, EPIC_SWORD_ID, 100);

        vm.expectRevert(abi.encodeWithSelector(ForgeItems.MaxSupplyExceeded.selector, EPIC_SWORD_ID, 1, 0));
        items.mintItem(alice, EPIC_SWORD_ID, 1);
    }

    function test_MintBatch() public {
        uint256[] memory ids = new uint256[](2);
        ids[0] = SWORD_ID;
        ids[1] = SHIELD_ID;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 5;
        amounts[1] = 10;

        items.mintBatch(alice, ids, amounts);

        assertEq(items.balanceOf(alice, SWORD_ID), 5);
        assertEq(items.balanceOf(alice, SHIELD_ID), 10);
    }

    function test_MintBatchMismatch() public {
        uint256[] memory ids = new uint256[](2);
        ids[0] = SWORD_ID;
        ids[1] = SHIELD_ID;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 5;

        vm.expectRevert(ForgeItems.ArrayLengthMismatch.selector);
        items.mintBatch(alice, ids, amounts);
    }

    function test_SetCraftFeeRecipient() public {
        items.setCraftFeeRecipient(bob);
        assertEq(items.craftFeeRecipient(), bob);

        vm.expectRevert(ForgeItems.ZeroAddress.selector);
        items.setCraftFeeRecipient(address(0));
    }

    function test_SupportsInterface() public view {
        assertTrue(items.supportsInterface(0xd9b67a26)); // ERC1155 Interface
    }

    function test_GetRecipeCount() public {
        uint256 beforeCount = items.getRecipeCount();
        uint256[] memory inputIds = new uint256[](1);
        inputIds[0] = SWORD_ID;
        uint256[] memory inputAmts = new uint256[](1);
        inputAmts[0] = 1;

        items.addCraftRecipe(EPIC_SWORD_ID, inputIds, inputAmts, 0, 0);
        assertEq(items.getRecipeCount(), beforeCount + 1);
    }

    // --- Fuzz Tests ---

    function testFuzz_MintDust(uint256 amount) public {
        amount = bound(amount, 0, 100_000_000);
        items.mintDust(alice, amount);
        assertEq(items.balanceOf(alice, DUST_ID), amount + 500); // 500 added in setUp
    }

    function testFuzz_MintItem(uint256 amount) public {
        amount = bound(amount, 0, 100);
        items.mintItem(alice, EPIC_SWORD_ID, amount);
        assertEq(items.balanceOf(alice, EPIC_SWORD_ID), amount);
    }
}
