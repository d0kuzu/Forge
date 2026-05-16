// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {ForgeCoin} from "../../src/tokens/ForgeCoin.sol";

contract ForgeCoinTest is Test {
    ForgeCoin public coin;
    address public admin = address(this);
    address public alice = address(0x1111);
    address public bob = address(0x2222);

    function setUp() public {
        coin = new ForgeCoin(admin, 1_000_000 * 1e18);
    }

    // --- Unit Tests ---

    function test_ConstructorSupplyLimit() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                ForgeCoin.MaxSupplyExceeded.selector,
                100_000_001 * 1e18,
                100_000_000 * 1e18
            )
        );
        new ForgeCoin(admin, 100_000_001 * 1e18);
    }

    function test_MintRoleRestricted() public {
        vm.prank(alice);
        vm.expectRevert();
        coin.mint(alice, 100 * 1e18);
    }

    function test_MintMaxSupplyExceeded() public {
        uint256 remaining = coin.maxSupply() - coin.totalSupply();
        coin.mint(alice, remaining);

        vm.expectRevert(
            abi.encodeWithSelector(
                ForgeCoin.MaxSupplyExceeded.selector,
                1,
                0
            )
        );
        coin.mint(alice, 1);
    }

    function test_GrantAndRevokeMinter() public {
        coin.grantMinterRole(alice);
        
        vm.prank(alice);
        coin.mint(bob, 100 * 1e18);
        assertEq(coin.balanceOf(bob), 100 * 1e18);

        coin.revokeMinterRole(alice);

        vm.prank(alice);
        vm.expectRevert();
        coin.mint(bob, 100 * 1e18);
    }

    function test_Burn() public {
        coin.mint(alice, 1000 * 1e18);
        
        vm.prank(alice);
        coin.burn(400 * 1e18);

        assertEq(coin.balanceOf(alice), 600 * 1e18);
    }

    function test_VotesDelegation() public {
        coin.mint(alice, 1000 * 1e18);
        assertEq(coin.getVotes(bob), 0);

        vm.prank(alice);
        coin.delegate(bob);

        assertEq(coin.getVotes(bob), 1000 * 1e18);
        
        // Transfer and check voting power update
        vm.prank(alice);
        coin.transfer(bob, 300 * 1e18);

        assertEq(coin.getVotes(bob), 700 * 1e18);
    }

    function test_MaxSupplyView() public view {
        assertEq(coin.maxSupply(), 100_000_000 * 1e18);
    }

    function test_SupportsInterface() public view {
        assertTrue(coin.supportsInterface(0x7965db0b)); // AccessControl interface
    }

    // --- Fuzz Tests ---

    function testFuzz_Mint(uint256 amount) public {
        amount = bound(amount, 0, coin.maxSupply() - coin.totalSupply());
        coin.mint(alice, amount);
        assertEq(coin.balanceOf(alice), amount);
    }

    function testFuzz_Burn(uint256 amount) public {
        uint256 mintAmt = 100_000 * 1e18;
        coin.mint(alice, mintAmt);

        amount = bound(amount, 0, mintAmt);
        vm.prank(alice);
        coin.burn(amount);
        assertEq(coin.balanceOf(alice), mintAmt - amount);
    }

    function testFuzz_VotingPowerDelegation(uint256 amount) public {
        amount = bound(amount, 0, coin.maxSupply() - coin.totalSupply());
        coin.mint(alice, amount);

        vm.prank(alice);
        coin.delegate(bob);

        assertEq(coin.getVotes(bob), amount);
    }
}
