// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {ForgeCoin} from "../src/tokens/ForgeCoin.sol";
import {ForgeItems} from "../src/tokens/ForgeItems.sol";
import {ForgeVault} from "../src/vaults/ForgeVault.sol";
import {NFTRentalVault} from "../src/vaults/NFTRentalVault.sol";
import {DataTypes} from "../src/libraries/DataTypes.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

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
        items = new ForgeItems(address(coin), admin, admin);

        // 1. Setup Staking Vault (5% performance fee)
        stakingVault = new ForgeVault(coin, admin, feeRecipient, 500);
        stakingVault.grantRole(stakingVault.DISTRIBUTOR_ROLE(), admin);

        // 2. Setup Rental Vault
        rentalVault = new NFTRentalVault(address(coin), address(items), admin);

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
        uint256 depositAmt = 1000 * 10**18;
        vm.startPrank(alice);
        coin.approve(address(stakingVault), depositAmt);
        stakingVault.deposit(depositAmt, alice);
        vm.stopPrank();

        assertEq(stakingVault.balanceOf(alice), depositAmt);
        assertEq(stakingVault.totalAssets(), depositAmt);

        uint256 rewardAmt = 100 * 10**18;
        coin.approve(address(stakingVault), rewardAmt);
        stakingVault.distributeRewards(rewardAmt);

        assertEq(coin.balanceOf(feeRecipient), 5 * 10**18);
        assertEq(stakingVault.totalAssets(), 1095 * 10**18);

        vm.prank(alice);
        uint256 withdrawn = stakingVault.redeem(depositAmt, alice, alice);
        assertApproxEqAbs(withdrawn, 1095 * 10**18, 1);
    }

    // ==========================================
    // NFTRentalVault Tests
    // ==========================================

    function test_ListAndRentNFT() public {
        vm.startPrank(alice);
        items.setApprovalForAll(address(rentalVault), true);
        
        uint256 pricePerDay = 10 * 10**18; 
        uint256 minDuration = 1 days;
        uint256 maxDuration = 7 days;

        uint256 listingId = rentalVault.listItem(1, 1, pricePerDay, minDuration, maxDuration);
        vm.stopPrank();

        assertEq(items.balanceOf(address(rentalVault), 1), 1);
        assertEq(items.balanceOf(alice, 1), 0);

        uint256 duration = 2 days;
        uint256 totalCost = 20 * 10**18;

        vm.startPrank(bob);
        coin.approve(address(rentalVault), totalCost);
        uint256 rentalId = rentalVault.rentItem(listingId, duration);
        vm.stopPrank();

        assertTrue(rentalVault.isRented(rentalId));
        assertEq(rentalVault.unclaimedRent(alice), 19.5 * 10**18);

        vm.warp(block.timestamp + 3 days);

        rentalVault.liquidateExpiredRental(rentalId);
        assertFalse(rentalVault.isRented(rentalId));

        vm.startPrank(alice);
        rentalVault.claimRent();
        rentalVault.delistItem(listingId);
        vm.stopPrank();

        assertEq(coin.balanceOf(alice), (10_000 * 10**18) + (19.5 * 10**18));
        assertEq(items.balanceOf(alice, 1), 1);
    }

    function test_ListZeroAmountReverts() public {
        vm.startPrank(alice);
        items.setApprovalForAll(address(rentalVault), true);
        vm.expectRevert(NFTRentalVault.ZeroAmount.selector);
        rentalVault.listItem(1, 0, 10 * 10**18, 1 days, 7 days);
        vm.stopPrank();
    }

    function test_ListDurationMismatchReverts() public {
        vm.startPrank(alice);
        items.setApprovalForAll(address(rentalVault), true);
        vm.expectRevert(abi.encodeWithSelector(NFTRentalVault.InvalidDuration.selector, 2 days, 2 days, 1 days));
        rentalVault.listItem(1, 1, 10 * 10**18, 2 days, 1 days);
        vm.stopPrank();
    }

    function test_DelistNotOwnerReverts() public {
        vm.startPrank(alice);
        items.setApprovalForAll(address(rentalVault), true);
        uint256 listingId = rentalVault.listItem(1, 1, 10 * 10**18, 1 days, 7 days);
        vm.stopPrank();

        vm.startPrank(bob);
        vm.expectRevert(abi.encodeWithSelector(NFTRentalVault.NotListingOwner.selector, listingId));
        rentalVault.delistItem(listingId);
        vm.stopPrank();
    }

    function test_DelistCurrentlyRentedReverts() public {
        vm.startPrank(alice);
        items.setApprovalForAll(address(rentalVault), true);
        uint256 listingId = rentalVault.listItem(1, 1, 10 * 10**18, 1 days, 7 days);
        vm.stopPrank();

        vm.startPrank(bob);
        coin.approve(address(rentalVault), 20 * 10**18);
        rentalVault.rentItem(listingId, 2 days);
        vm.stopPrank();

        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(NFTRentalVault.ItemCurrentlyRented.selector, listingId));
        rentalVault.delistItem(listingId);
        vm.stopPrank();
    }

    function test_UpdateListing() public {
        vm.startPrank(alice);
        items.setApprovalForAll(address(rentalVault), true);
        uint256 listingId = rentalVault.listItem(1, 1, 10 * 10**18, 1 days, 7 days);

        rentalVault.updateListing(listingId, 15 * 10**18, 2 days, 5 days);
        vm.stopPrank();

        DataTypes.RentalListing memory listing = rentalVault.getListing(listingId);
        assertEq(listing.pricePerDay, 15 * 10**18);
        assertEq(listing.minDuration, 2 days);
        assertEq(listing.maxDuration, 5 days);
    }

    function test_RentDurationBoundsReverts() public {
        vm.startPrank(alice);
        items.setApprovalForAll(address(rentalVault), true);
        uint256 listingId = rentalVault.listItem(1, 1, 10 * 10**18, 1 days, 7 days);
        vm.stopPrank();

        vm.startPrank(bob);
        coin.approve(address(rentalVault), 100 * 10**18);
        
        vm.expectRevert(abi.encodeWithSelector(NFTRentalVault.InvalidDuration.selector, 12 hours, 1 days, 7 days));
        rentalVault.rentItem(listingId, 12 hours);

        vm.expectRevert(abi.encodeWithSelector(NFTRentalVault.InvalidDuration.selector, 8 days, 1 days, 7 days));
        rentalVault.rentItem(listingId, 8 days);
        vm.stopPrank();
    }

    function test_ReturnItemEarly() public {
        vm.startPrank(alice);
        items.setApprovalForAll(address(rentalVault), true);
        uint256 listingId = rentalVault.listItem(1, 1, 10 * 10**18, 1 days, 7 days);
        vm.stopPrank();

        vm.startPrank(bob);
        coin.approve(address(rentalVault), 20 * 10**18);
        uint256 rentalId = rentalVault.rentItem(listingId, 2 days);
        
        rentalVault.returnItem(rentalId);
        vm.stopPrank();

        assertFalse(rentalVault.isRented(rentalId));
    }

    function test_ClaimRentNothingToClaim() public {
        vm.startPrank(alice);
        vm.expectRevert(NFTRentalVault.NothingToClaim.selector);
        rentalVault.claimRent();
        vm.stopPrank();
    }

    function test_SetForgeVault() public {
        rentalVault.setForgeVault(address(stakingVault));
        assertEq(address(rentalVault.forgeVault()), address(stakingVault));

        vm.expectRevert(NFTRentalVault.ZeroAddress.selector);
        rentalVault.setForgeVault(address(0));
    }

    function test_SweepPlatformFees() public {
        vm.startPrank(alice);
        items.setApprovalForAll(address(rentalVault), true);
        uint256 listingId = rentalVault.listItem(1, 1, 10 * 10**18, 1 days, 7 days);
        vm.stopPrank();

        vm.startPrank(bob);
        coin.approve(address(rentalVault), 20 * 10**18);
        rentalVault.rentItem(listingId, 2 days);
        vm.stopPrank();

        // Platform fee BPS = 2.5%. Of 20 FGC, fee is 0.5 FGC
        assertEq(rentalVault.accumulatedPlatformFees(), 0.5 * 10**18);

        rentalVault.setForgeVault(address(stakingVault));
        stakingVault.grantRole(stakingVault.DISTRIBUTOR_ROLE(), address(rentalVault));

        rentalVault.sweepPlatformFees();
        assertEq(rentalVault.accumulatedPlatformFees(), 0);
    }

    // --- Fuzz Tests ---

    function testFuzz_RentalPrice(uint256 dailyPrice) public {
        dailyPrice = bound(dailyPrice, 1 * 10**18, 1000 * 10**18);

        vm.startPrank(alice);
        items.setApprovalForAll(address(rentalVault), true);
        uint256 listingId = rentalVault.listItem(1, 1, dailyPrice, 1 days, 7 days);
        vm.stopPrank();

        uint256 totalCost = dailyPrice; // 1 day
        coin.transfer(bob, totalCost);

        vm.startPrank(bob);
        coin.approve(address(rentalVault), totalCost);
        uint256 rentalId = rentalVault.rentItem(listingId, 1 days);
        vm.stopPrank();

        assertTrue(rentalId > 0);
    }
}
