// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {ForgeCoin} from "../src/tokens/ForgeCoin.sol";
import {ForgeItems} from "../src/tokens/ForgeItems.sol";
import {ForgeVault} from "../src/vaults/ForgeVault.sol";
import {NFTRentalVault} from "../src/vaults/NFTRentalVault.sol";
import {DataTypes} from "../src/libraries/DataTypes.sol";

contract VaultsTest is Test {
    ForgeCoin public coin;
    ForgeItems public items;
    ForgeVault public stakingVault;
    NFTRentalVault public rentalVault;

    address public admin = address(this);
    address public feeRecipient = address(0x999);
    address public alice = address(0x1111);
    address public bob = address(0x2222);

    function setUp() public {
        coin = new ForgeCoin(admin, 1_000_000 * 10**18);
        items = new ForgeItems(address(coin), admin, admin, "");

        // 1. Setup Staking Vault (5% performance fee)
        stakingVault = new ForgeVault(coin, admin, feeRecipient, 500);
        stakingVault.grantRole(stakingVault.DISTRIBUTOR_ROLE(), admin);

        // 2. Setup Rental Vault
        rentalVault = new NFTRentalVault(address(coin), address(items));

        // Fund users
        coin.transfer(alice, 10_000 * 10**18);
        coin.transfer(bob, 10_000 * 10**18);

        items.defineItem(1, "Sword", DataTypes.Rarity.Common, 0, false);
        items.mintItem(alice, 1, 1); // Alice gets 1 sword
    }

    // ==========================================
    // ForgeVault Tests
    // ==========================================

    function test_StakingAndRewards() public {
        // Alice deposits 1000 Coins
        uint256 depositAmt = 1000 * 10**18;
        vm.startPrank(alice);
        coin.approve(address(stakingVault), depositAmt);
        stakingVault.deposit(depositAmt, alice);
        vm.stopPrank();

        // 1:1 ratio initially
        assertEq(stakingVault.balanceOf(alice), depositAmt);
        assertEq(stakingVault.totalAssets(), depositAmt);

        // Admin distributes 100 Coins as rewards
        uint256 rewardAmt = 100 * 10**18;
        coin.approve(address(stakingVault), rewardAmt);
        stakingVault.distributeRewards(rewardAmt);

        // Performance fee = 5% of 100 = 5 Coins
        assertEq(coin.balanceOf(feeRecipient), 5 * 10**18);
        
        // Vault total assets should be 1000 + 95 = 1095
        assertEq(stakingVault.totalAssets(), 1095 * 10**18);

        // Alice withdraws all shares
        vm.prank(alice);
        uint256 withdrawn = stakingVault.redeem(depositAmt, alice, alice);

        // Alice should get ~1095 (accounting for ERC4626 1-wei rounding down)
        assertApproxEqAbs(withdrawn, 1095 * 10**18, 1);
    }

    // ==========================================
    // NFTRentalVault Tests
    // ==========================================

    function test_ListAndRentNFT() public {
        // Alice lists her Sword
        vm.startPrank(alice);
        items.setApprovalForAll(address(rentalVault), true);
        
        uint256 pricePerDay = 10 * 10**18; // 10 coins / day
        uint256 minDuration = 1 days;
        uint256 maxDuration = 7 days;

        uint256 listingId = rentalVault.listItem(1, 1, pricePerDay, minDuration, maxDuration);
        vm.stopPrank();

        // Sword is in vault
        assertEq(items.balanceOf(address(rentalVault), 1), 1);
        assertEq(items.balanceOf(alice, 1), 0);

        // Bob rents the Sword for 2 days
        uint256 duration = 2 days;
        uint256 totalCost = 20 * 10**18; // 2 days * 10 coins

        vm.startPrank(bob);
        coin.approve(address(rentalVault), totalCost);
        uint256 rentalId = rentalVault.rentItem(listingId, duration);
        vm.stopPrank();

        // Check rental active
        assertTrue(rentalVault.isRented(rentalId));
        
        // Unclaimed rent for Alice (minus 2.5% platform fee)
        // Platform fee = 2.5% of 20 = 0.5 Coins
        // Alice gets = 19.5 Coins
        assertEq(rentalVault.unclaimedRent(alice), 19.5 * 10**18);

        // Fast forward 3 days (rental expired)
        vm.warp(block.timestamp + 3 days);

        // Anyone can liquidate
        rentalVault.liquidateExpiredRental(rentalId);
        assertFalse(rentalVault.isRented(rentalId));

        // Alice claims rent and delists item
        vm.startPrank(alice);
        rentalVault.claimRent();
        rentalVault.delistItem(listingId);
        vm.stopPrank();

        // Alice has her rent and her sword back
        assertEq(coin.balanceOf(alice), (10_000 * 10**18) + (19.5 * 10**18));
        assertEq(items.balanceOf(alice, 1), 1);
    }
}
