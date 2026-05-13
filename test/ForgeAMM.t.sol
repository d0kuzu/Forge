// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {ForgeCoin} from "../src/tokens/ForgeCoin.sol";
import {ForgeItems} from "../src/tokens/ForgeItems.sol";
import {ForgeAMM} from "../src/amm/ForgeAMM.sol";
import {ForgeLPToken} from "../src/amm/ForgeLPToken.sol";
import {AMMath} from "../src/libraries/AMMath.sol";

contract ForgeAMMTest is Test {
    ForgeCoin public coin;
    ForgeItems public items;
    ForgeAMM public amm;
    ForgeLPToken public lpToken;

    address public admin = address(this);
    address public alice = address(0x1111);
    address public bob = address(0x2222);

    uint256 constant INITIAL_COIN_MINT = 1_000_000 * 10**18;
    uint256 constant INITIAL_DUST_MINT = 1_000_000 * 10**18;

    function setUp() public {
        // 1. Deploy tokens
        coin = new ForgeCoin(admin, 0); // initialAdmin, initialSupply
        items = new ForgeItems(address(coin), admin, admin);
        items.setURI("https://api.forge.com/items/");

        // 2. Grant minter roles to this test contract
        coin.grantRole(coin.MINTER_ROLE(), address(this));
        items.grantRole(items.MINTER_ROLE(), address(this));

        // 3. Deploy AMM
        amm = new ForgeAMM(address(coin), address(items));
        lpToken = amm.lpToken();

        // 4. Mint tokens to Alice and Bob
        coin.mint(alice, INITIAL_COIN_MINT);
        items.mintDust(alice, INITIAL_DUST_MINT);

        coin.mint(bob, INITIAL_COIN_MINT);
        items.mintDust(bob, INITIAL_DUST_MINT);

        // 5. Approvals
        vm.startPrank(alice);
        coin.approve(address(amm), type(uint256).max);
        items.setApprovalForAll(address(amm), true);
        vm.stopPrank();

        vm.startPrank(bob);
        coin.approve(address(amm), type(uint256).max);
        items.setApprovalForAll(address(amm), true);
        vm.stopPrank();
    }

    function test_InitialLiquidity() public {
        uint256 coinAmount = 1000 * 10**18;
        uint256 dustAmount = 1000 * 10**18;

        vm.startPrank(alice);
        uint256 lpMinted = amm.addLiquidity(
            coinAmount,
            dustAmount,
            0,
            0,
            block.timestamp + 100
        );
        vm.stopPrank();

        // Expected LP = sqrt(1000e18 * 1000e18) - 1000 (MINIMUM_LIQUIDITY)
        // sqrt(1_000_000 * 1e36) = 1000e18
        uint256 expectedLP = (1000 * 10**18) - amm.MINIMUM_LIQUIDITY();
        
        assertEq(lpMinted, expectedLP);
        assertEq(lpToken.balanceOf(alice), expectedLP);

        (uint256 resCoin, uint256 resDust, ) = amm.getReserves();
        assertEq(resCoin, coinAmount);
        assertEq(resDust, dustAmount);
    }

    function test_SwapCoinForDust() public {
        // Setup initial liquidity (1:1 price)
        uint256 liqAmount = 10_000 * 10**18;
        vm.prank(alice);
        amm.addLiquidity(liqAmount, liqAmount, 0, 0, block.timestamp + 100);

        // Bob swaps 100 Coins for Dust
        uint256 swapAmount = 100 * 10**18;
        
        // Calculate expected manually (0.3% fee)
        // amountInWithFee = 100 * 997 = 99700
        // num = 99700 * 10_000 = 997_000_000
        // den = 10_000 * 1000 + 99700 = 10_099_700
        // expectedOut = num / den ~ 98.71...
        
        uint256 expectedOut = amm.getAmountOut(swapAmount, liqAmount, liqAmount);

        uint256 bobDustBefore = items.balanceOf(bob, 0);

        vm.prank(bob);
        uint256 actualOut = amm.swapForgeCoinForDust(swapAmount, 0, block.timestamp + 100);

        uint256 bobDustAfter = items.balanceOf(bob, 0);

        assertEq(actualOut, expectedOut);
        assertEq(bobDustAfter - bobDustBefore, expectedOut);

        (uint256 resCoin, uint256 resDust, ) = amm.getReserves();
        assertEq(resCoin, liqAmount + swapAmount);
        assertEq(resDust, liqAmount - expectedOut);
    }

    function test_SwapDustForCoin() public {
        // Setup initial liquidity (1:1 price)
        uint256 liqAmount = 10_000 * 10**18;
        vm.prank(alice);
        amm.addLiquidity(liqAmount, liqAmount, 0, 0, block.timestamp + 100);

        // Bob swaps 500 Dust for Coin
        uint256 swapAmount = 500 * 10**18;
        
        uint256 expectedOut = amm.getAmountOut(swapAmount, liqAmount, liqAmount);

        uint256 bobCoinBefore = coin.balanceOf(bob);

        vm.prank(bob);
        uint256 actualOut = amm.swapDustForForgeCoin(swapAmount, 0, block.timestamp + 100);

        uint256 bobCoinAfter = coin.balanceOf(bob);

        assertEq(actualOut, expectedOut);
        assertEq(bobCoinAfter - bobCoinBefore, expectedOut);
    }

    function test_RevertIfSlippageExceeded() public {
        // Setup initial liquidity (1:1 price)
        uint256 liqAmount = 10_000 * 10**18;
        vm.prank(alice);
        amm.addLiquidity(liqAmount, liqAmount, 0, 0, block.timestamp + 100);

        uint256 swapAmount = 100 * 10**18;
        uint256 expectedOut = amm.getAmountOut(swapAmount, liqAmount, liqAmount);

        vm.prank(bob);
        vm.expectRevert(ForgeAMM.SlippageExceeded.selector);
        // Request 1 wei more than possible
        amm.swapForgeCoinForDust(swapAmount, expectedOut + 1, block.timestamp + 100);
    }

    function test_MathYulOptimizations() public {
        // Test sqrt
        assertEq(AMMath.sqrt(144), 12);
        assertEq(AMMath.sqrt(0), 0);
        assertEq(AMMath.sqrt(3), 1);
        assertEq(AMMath.sqrt(10**36), 10**18);

        // Test safeMul
        assertEq(AMMath.safeMul(5, 10), 50);
        assertEq(AMMath.safeMul(0, 100), 0);
        assertEq(AMMath.safeMul(100, 0), 0);

        // Test min
        assertEq(AMMath.min(5, 10), 5);
        assertEq(AMMath.min(10, 5), 5);
        assertEq(AMMath.min(7, 7), 7);
    }
}
