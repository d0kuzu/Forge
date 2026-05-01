// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {ForgeCoin} from "../src/tokens/ForgeCoin.sol";
import {ForgeItems} from "../src/tokens/ForgeItems.sol";
import {GachaLootbox} from "../src/gacha/GachaLootbox.sol";
import {MockVRFCoordinator} from "./mocks/MockVRFCoordinator.sol";
import {DataTypes} from "../src/libraries/DataTypes.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract GachaLootboxTest is Test {
    ForgeCoin public coin;
    ForgeItems public items;
    GachaLootbox public impl;
    GachaLootbox public gacha;
    MockVRFCoordinator public vrfMock;

    address public admin = address(this);
    address public alice = address(0x1111);
    
    uint256 constant LOOTBOX_TYPE = 1;
    uint256 constant LOOTBOX_PRICE = 10 * 10**18;
    uint256 constant DUST_DROP_AMOUNT = 50;

    function setUp() public {
        coin = new ForgeCoin(admin, 1000 * 10**18);
        items = new ForgeItems(address(coin), admin, admin, "");
        vrfMock = new MockVRFCoordinator();

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
        coin.transfer(alice, 100 * 10**18);
        vm.prank(alice);
        coin.approve(address(gacha), type(uint256).max);
    }

    function test_OpenLootboxAndFulfill() public {
        uint256 aliceCoinBefore = coin.balanceOf(alice);

        // 1. Open Lootbox
        vm.prank(alice);
        uint256 reqId = gacha.openLootbox(LOOTBOX_TYPE);

        assertEq(coin.balanceOf(alice), aliceCoinBefore - LOOTBOX_PRICE);
        assertEq(gacha.totalRevenue(), LOOTBOX_PRICE);
        assertEq(vrfMock.getPendingRequestCount(), 1);

        // 2. Fulfill VRF
        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = 15; // 15 < 30 (Sword weight) -> should drop Sword (id 1)

        vrfMock.fulfillRandomWords(reqId, randomWords);

        // Alice should have 1 Sword
        assertEq(items.balanceOf(alice, 1), 1);
        
        // Request should be marked fulfilled
        DataTypes.GachaRequest memory req = gacha.getRequest(reqId);
        assertTrue(req.fulfilled);
    }

    function test_OpenLootboxDustDrop() public {
        vm.prank(alice);
        uint256 reqId = gacha.openLootbox(LOOTBOX_TYPE);

        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = 70; // 70 > 50 (Sword+Shield) -> falls into Dust category (weight 50, total 100)

        vrfMock.fulfillRandomWords(reqId, randomWords);

        // Alice should have DUST_DROP_AMOUNT
        assertEq(items.balanceOf(alice, 0), DUST_DROP_AMOUNT);
    }

    function test_RevertOpenInactiveLootbox() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(GachaLootbox.LootboxNotActive.selector, 99));
        gacha.openLootbox(99);
    }
}
