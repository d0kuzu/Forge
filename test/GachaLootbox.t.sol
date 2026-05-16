// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {ForgeCoin} from "../src/tokens/ForgeCoin.sol";
import {ForgeItems} from "../src/tokens/ForgeItems.sol";
import {GachaLootbox} from "../src/gacha/GachaLootbox.sol";
import {ForgeVault} from "../src/vaults/ForgeVault.sol";
import {MockVRFCoordinator} from "./mocks/MockVRFCoordinator.sol";
import {DataTypes} from "../src/libraries/DataTypes.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract GachaLootboxTest is Test {
    ForgeCoin public coin;
    ForgeItems public items;
    ForgeVault public vault;
    GachaLootbox public impl;
    GachaLootbox public gacha;
    MockVRFCoordinator public vrfMock;

    address public admin = address(this);
    address public alice = address(0x1111);
    address public bob = address(0x2222);
    
    uint256 constant LOOTBOX_TYPE = 1;
    uint256 constant LOOTBOX_PRICE = 10 * 10**18;
    uint256 constant DUST_DROP_AMOUNT = 50;

    function setUp() public {
        coin = new ForgeCoin(admin, 1_000_000 * 10**18);
        items = new ForgeItems(address(coin), admin, admin);
        vrfMock = new MockVRFCoordinator();
        vault = new ForgeVault(IERC20(address(coin)), admin, admin, 500);

        // Seed Staking Vault to avoid first staker skew
        coin.approve(address(vault), 10 * 10**18);
        vault.deposit(10 * 10**18, admin);

        // Deploy Gacha implementation and Proxy
        impl = new GachaLootbox();
        bytes memory initData = abi.encodeWithSelector(
            GachaLootbox.initialize.selector,
            admin,
            address(coin),
            address(items),
            address(vrfMock),
            1, // subId
            bytes32(0), // keyHash
            100000, // gasLimit
            3, // confirmations
            DUST_DROP_AMOUNT
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        gacha = GachaLootbox(address(proxy));

        // Grant roles
        items.grantRole(items.MINTER_ROLE(), address(gacha));
        vault.grantRole(vault.DISTRIBUTOR_ROLE(), address(gacha));

        // Configure Lootbox (Item 1, 2, and 0(Dust))
        items.defineItem(1, "Sword", DataTypes.Rarity.Common, 0, false);
        items.defineItem(2, "Shield", DataTypes.Rarity.Common, 0, false);

        uint256[] memory ids = new uint256[](3);
        ids[0] = 1; // Sword
        ids[1] = 2; // Shield
        ids[2] = 0; // Dust

        uint256[] memory weights = new uint256[](3);
        weights[0] = 30; // 30%
        weights[1] = 20; // 20%
        weights[2] = 50; // 50%

        gacha.configureLootbox(LOOTBOX_TYPE, LOOTBOX_PRICE, ids, weights);

        // Setup Alice
        coin.transfer(alice, 1000 * 10**18);
        vm.prank(alice);
        coin.approve(address(gacha), type(uint256).max);
    }

    // --- Unit Tests ---

    function test_OpenLootboxAndFulfill() public {
        gacha.setForgeVault(address(vault));
        uint256 aliceCoinBefore = coin.balanceOf(alice);

        // 1. Open Lootbox
        vm.prank(alice);
        uint256 reqId = gacha.openLootbox(LOOTBOX_TYPE);

        assertEq(coin.balanceOf(alice), aliceCoinBefore - LOOTBOX_PRICE);
        assertEq(gacha.totalRevenue(), LOOTBOX_PRICE);
        assertEq(vrfMock.getPendingRequestCount(), 1);

        // 2. Fulfill VRF
        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = 15; // 15 < 30 -> Sword

        vrfMock.fulfillRandomWords(reqId, randomWords);

        assertEq(items.balanceOf(alice, 1), 1);
        
        DataTypes.GachaRequest memory req = gacha.getRequest(reqId);
        assertTrue(req.fulfilled);
    }

    function test_OpenLootboxDustDrop() public {
        vm.prank(alice);
        uint256 reqId = gacha.openLootbox(LOOTBOX_TYPE);

        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = 70; // Dust drop

        vrfMock.fulfillRandomWords(reqId, randomWords);

        assertEq(items.balanceOf(alice, 0), DUST_DROP_AMOUNT);
    }

    function test_RevertOpenInactiveLootbox() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(GachaLootbox.LootboxNotActive.selector, 99));
        gacha.openLootbox(99);
    }

    function test_ConfigureLootboxArrayMismatch() public {
        uint256[] memory ids = new uint256[](2);
        ids[0] = 1;
        ids[1] = 2;

        uint256[] memory weights = new uint256[](1);
        weights[0] = 100;

        vm.expectRevert(GachaLootbox.ArrayLengthMismatch.selector);
        gacha.configureLootbox(2, 5 * 10**18, ids, weights);
    }

    function test_ConfigureLootboxInvalidWeights() public {
        uint256[] memory ids = new uint256[](1);
        ids[0] = 1;

        uint256[] memory weights = new uint256[](1);
        weights[0] = 0;

        vm.expectRevert(GachaLootbox.InvalidWeights.selector);
        gacha.configureLootbox(2, 5 * 10**18, ids, weights);
    }

    function test_UpdateDropRates() public {
        uint256[] memory newWeights = new uint256[](3);
        newWeights[0] = 50;
        newWeights[1] = 10;
        newWeights[2] = 40;

        gacha.updateDropRates(LOOTBOX_TYPE, newWeights);

        DataTypes.LootboxConfig memory config = gacha.getLootboxConfig(LOOTBOX_TYPE);
        assertEq(config.weights[0], 50);
        assertEq(config.totalWeight, 100);
    }

    function test_UpdateDropRatesReverts() public {
        uint256[] memory newWeights = new uint256[](3);

        vm.expectRevert(abi.encodeWithSelector(GachaLootbox.LootboxNotActive.selector, 99));
        gacha.updateDropRates(99, newWeights);

        newWeights = new uint256[](1);
        vm.expectRevert(GachaLootbox.ArrayLengthMismatch.selector);
        gacha.updateDropRates(LOOTBOX_TYPE, newWeights);
    }

    function test_SetPrice() public {
        gacha.setPrice(LOOTBOX_TYPE, 15 * 10**18);
        DataTypes.LootboxConfig memory config = gacha.getLootboxConfig(LOOTBOX_TYPE);
        assertEq(config.priceInForgeCoin, 15 * 10**18);

        vm.expectRevert(abi.encodeWithSelector(GachaLootbox.LootboxNotActive.selector, 99));
        gacha.setPrice(99, 5 * 10**18);
    }

    function test_WithdrawRevenue() public {
        vm.prank(alice);
        gacha.openLootbox(LOOTBOX_TYPE);

        uint256 balanceBefore = coin.balanceOf(bob);
        gacha.withdrawRevenue(bob, LOOTBOX_PRICE);
        assertEq(coin.balanceOf(bob), balanceBefore + LOOTBOX_PRICE);
    }

    function test_WithdrawRevenueReverts() public {
        vm.expectRevert(GachaLootbox.ZeroAddress.selector);
        gacha.withdrawRevenue(address(0), 1);

        vm.expectRevert(abi.encodeWithSelector(GachaLootbox.InsufficientRevenue.selector, 100, 0));
        gacha.withdrawRevenue(bob, 100);
    }

    function test_SweepRevenue() public {
        // Initially, forgeVault is address(0) from setup.
        // Let's open a lootbox to accumulate revenue in the contract.
        vm.prank(alice);
        gacha.openLootbox(LOOTBOX_TYPE);

        assertEq(coin.balanceOf(address(gacha)), LOOTBOX_PRICE);

        gacha.setForgeVault(address(vault));
        gacha.sweepRevenue();

        assertEq(coin.balanceOf(address(gacha)), 0);
    }

    function test_SweepRevenueZeroAddress() public {
        vm.expectRevert(GachaLootbox.ZeroAddress.selector);
        gacha.sweepRevenue();
    }

    function test_PauseAndUnpause() public {
        gacha.pause();

        vm.prank(alice);
        vm.expectRevert(); // should revert when paused
        gacha.openLootbox(LOOTBOX_TYPE);

        gacha.unpause();

        vm.prank(alice);
        gacha.openLootbox(LOOTBOX_TYPE);
    }

    function test_AdminFunctionsZeroAddresses() public {
        vm.expectRevert(GachaLootbox.ZeroAddress.selector);
        gacha.setVRFCoordinator(address(0));

        vm.expectRevert(GachaLootbox.ZeroAddress.selector);
        gacha.setForgeVault(address(0));
    }

    function test_UpdateVRFConfig() public {
        gacha.updateVRFConfig(10, bytes32(uint256(1)), 200000, 5);
        assertEq(gacha.s_subscriptionId(), 10);
        assertEq(gacha.s_keyHash(), bytes32(uint256(1)));
        assertEq(gacha.s_callbackGasLimit(), 200000);
        assertEq(gacha.s_requestConfirmations(), 5);
    }

    function test_SetDustDropAmount() public {
        gacha.setDustDropAmount(100);
        assertEq(gacha.dustDropAmount(), 100);
    }

    // --- Fuzz Tests ---

    function testFuzz_OpenLootboxPrice(uint256 price) public {
        price = bound(price, 1 * 10**18, 500 * 10**18);
        gacha.setPrice(LOOTBOX_TYPE, price);

        coin.transfer(bob, price);
        vm.startPrank(bob);
        coin.approve(address(gacha), price);
        
        uint256 reqId = gacha.openLootbox(LOOTBOX_TYPE);
        assertTrue(reqId > 0);
        vm.stopPrank();
    }
}
