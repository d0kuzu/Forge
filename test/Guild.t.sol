// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {ForgeCoin} from "../src/tokens/ForgeCoin.sol";
import {GuildFactory} from "../src/factory/GuildFactory.sol";
import {Guild} from "../src/factory/Guild.sol";

contract GuildTest is Test {
    ForgeCoin public coin;
    GuildFactory public factory;

    address public admin = address(this);
    address public alice = address(0x1111);
    address public bob = address(0x2222);

    function setUp() public {
        coin = new ForgeCoin(admin, 1_000_000 * 10**18);
        factory = new GuildFactory();
        
        coin.transfer(alice, 10_000 * 10**18);
        coin.transfer(bob, 10_000 * 10**18);
    }

    function test_DeterministicDeployment() public {
        string memory name = "Knights of the Forge";
        bytes32 salt = keccak256("salt_1");

        // 1. Predict address
        address predicted = factory.predictGuildAddress(name, alice, salt);

        // 2. Deploy
        address deployed = factory.createGuild(name, alice, salt);

        // 3. Verify
        assertEq(predicted, deployed);
        assertTrue(factory.isGuild(deployed));
        assertEq(factory.getGuildCount(), 1);

        Guild guild = Guild(payable(deployed));
        assertEq(guild.name(), name);
        assertEq(guild.leader(), alice);
        assertTrue(guild.isMember(alice));
        assertEq(guild.memberCount(), 1);
    }

    function test_GuildMembershipAndTreasury() public {
        string memory name = "Warriors";
        bytes32 salt = keccak256("salt_2");
        address deployed = factory.createGuild(name, alice, salt);
        Guild guild = Guild(payable(deployed));

        // Alice adds Bob
        vm.prank(alice);
        guild.addMember(bob);

        assertTrue(guild.isMember(bob));
        assertEq(guild.memberCount(), 2);

        // Bob funds the treasury
        vm.prank(bob);
        coin.transfer(deployed, 1000 * 10**18);
        assertEq(coin.balanceOf(deployed), 1000 * 10**18);

        // Alice (leader) withdraws from treasury
        vm.prank(alice);
        guild.withdrawTreasury(address(coin), alice, 500 * 10**18);

        assertEq(coin.balanceOf(deployed), 500 * 10**18);
        
        // Alice transfers leadership to Bob
        vm.prank(alice);
        guild.transferLeadership(bob);

        assertEq(guild.leader(), bob);
    }

    function test_RevertDeployDuplicate() public {
        string memory name = "Duplicate";
        bytes32 salt = keccak256("salt_dup");

        factory.createGuild(name, alice, salt);

        // CREATE2 will revert on duplicate deployment (same salt, same initcode)
        vm.expectRevert(); 
        factory.createGuild(name, alice, salt);
    }
}
