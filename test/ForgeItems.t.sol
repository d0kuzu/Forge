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

    uint256 constant DUST_ID = 0;
    uint256 constant SWORD_ID = 1;
    uint256 constant SHIELD_ID = 2;
    uint256 constant EPIC_SWORD_ID = 3;

    function setUp() public {
        coin = new ForgeCoin(admin, 1_000_000 * 10**18);
        items = new ForgeItems(address(coin), admin, treasury, "https://api.forge.com/items/");

        coin.transfer(alice, 1000 * 10**18);
        items.mintDust(alice, 500);

        // Define Items
        items.defineItem(SWORD_ID, "Basic Sword", DataTypes.Rarity.Common, 0, true);
        items.defineItem(SHIELD_ID, "Basic Shield", DataTypes.Rarity.Common, 0, true);
        items.defineItem(EPIC_SWORD_ID, "Epic Sword", DataTypes.Rarity.Epic, 100, true); // Max supply 100, craftable=true
    }

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

    function test_AddAndCraftRecipe() public {
        // Give Alice required inputs
        items.mintItem(alice, SWORD_ID, 2);
        
        uint256[] memory inputIds = new uint256[](1);
        inputIds[0] = SWORD_ID;
        
        uint256[] memory inputAmts = new uint256[](1);
        inputAmts[0] = 2; // Need 2 basic swords

        // Cost: 2 Basic Swords + 100 Dust + 50 ForgeCoin -> 1 Epic Sword
        uint256 recipeId = items.addCraftRecipe(
            EPIC_SWORD_ID,
            inputIds,
            inputAmts,
            100, // dustCost
            50 * 10**18 // forgeCoinCost
        );

        vm.startPrank(alice);
        coin.approve(address(items), 50 * 10**18);
        
        uint256 aliceCoinBefore = coin.balanceOf(alice);
        uint256 aliceDustBefore = items.balanceOf(alice, DUST_ID);
        
        // Execute craft
        items.craft(recipeId);
        vm.stopPrank();

        // Verifications
        assertEq(items.balanceOf(alice, EPIC_SWORD_ID), 1);
        assertEq(items.balanceOf(alice, SWORD_ID), 0); // 2 burned
        assertEq(items.balanceOf(alice, DUST_ID), aliceDustBefore - 100);
        assertEq(coin.balanceOf(alice), aliceCoinBefore - 50 * 10**18);
        assertEq(coin.balanceOf(treasury), 50 * 10**18); // Fee went to treasury
    }

    function test_RevertCraftIfInsufficientMaterials() public {
        uint256[] memory inputIds = new uint256[](1);
        inputIds[0] = SWORD_ID;
        uint256[] memory inputAmts = new uint256[](1);
        inputAmts[0] = 5; // Alice only has 0 currently

        uint256 recipeId = items.addCraftRecipe(EPIC_SWORD_ID, inputIds, inputAmts, 0, 0);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(ForgeItems.InsufficientCraftingMaterials.selector, SWORD_ID, 5, 0));
        items.craft(recipeId);
    }

    function test_MaxSupplyEnforcement() public {
        // Mint Epic Sword to its limit (100)
        items.mintItem(alice, EPIC_SWORD_ID, 100);

        // Attempting to mint 1 more should fail
        vm.expectRevert(abi.encodeWithSelector(ForgeItems.MaxSupplyExceeded.selector, EPIC_SWORD_ID, 1, 0));
        items.mintItem(alice, EPIC_SWORD_ID, 1);
    }
}
