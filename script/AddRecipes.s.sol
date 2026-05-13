// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {ForgeItems} from "../src/tokens/ForgeItems.sol";
import {DataTypes} from "../src/libraries/DataTypes.sol";

contract AddRecipesScript is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envOr("PRIVATE_KEY", uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80));
        address deployer = vm.addr(deployerPrivateKey);
        console2.log("Running AddRecipes with address:", deployer);

        // Deployed ForgeItems address on Base Sepolia
        address itemsAddress = 0x32F9759fD5FC6383Eae512e34962aAee0069bf66;
        ForgeItems items = ForgeItems(itemsAddress);

        vm.startBroadcast(deployerPrivateKey);

        // 1. Define Upgraded Shield (ID 3) and Upgraded Sword (ID 4)
        items.defineItem(3, "Upgraded Shield", DataTypes.Rarity.Uncommon, 0, true);
        items.defineItem(4, "Upgraded Sword", DataTypes.Rarity.Uncommon, 0, true);
        console2.log("Upgraded items defined successfully.");

        // 2. Add Recipe 0 (Upgraded Shield): requires 1 Iron Shield (ID 2) and 100 Dust (ID 0)
        uint256[] memory inputsShield = new uint256[](1);
        inputsShield[0] = 2; // Iron Shield
        uint256[] memory amountsShield = new uint256[](1);
        amountsShield[0] = 1;

        uint256 recipeId0 = items.addCraftRecipe(
            3,             // resultItemId
            inputsShield,  // inputItemIds
            amountsShield, // inputAmounts
            100 * 10**18,  // dustCost
            0              // forgeCoinCost
        );
        console2.log("Recipe 0 (Upgraded Shield) added with ID:", recipeId0);

        // 3. Add Recipe 1 (Upgraded Sword): requires 1 Iron Sword (ID 1) and 100 Dust (ID 0)
        uint256[] memory inputsSword = new uint256[](1);
        inputsSword[0] = 1; // Iron Sword
        uint256[] memory amountsSword = new uint256[](1);
        amountsSword[0] = 1;

        uint256 recipeId1 = items.addCraftRecipe(
            4,            // resultItemId
            inputsSword,  // inputItemIds
            amountsSword, // inputAmounts
            100 * 10**18, // dustCost
            0             // forgeCoinCost
        );
        console2.log("Recipe 1 (Upgraded Sword) added with ID:", recipeId1);

        vm.stopBroadcast();
        console2.log("Recipes setup complete!");
    }
}
