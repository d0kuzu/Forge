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
        coin = new ForgeCoin(admin, 0); 
        items = new ForgeItems(address(coin), admin, admin);
        items.setURI("https://api.forge.com/items/");

        coin.grantRole(coin.MINTER_ROLE(), address(this));
        items.grantRole(items.MINTER_ROLE(), address(this));

        amm = new ForgeAMM(address(coin), address(items));
        lpToken = amm.lpToken();

        coin.mint(alice, INITIAL_COIN_MINT);
        items.mintDust(alice, INITIAL_DUST_MINT);

        coin.mint(bob, INITIAL_COIN_MINT);
        items.mintDust(bob, INITIAL_DUST_MINT);

        vm.startPrank(alice);
        coin.approve(address(amm), type(uint256).max);
        items.setApprovalForAll(address(amm), true);
        vm.stopPrank();

        vm.startPrank(bob);
        coin.approve(address(amm), type(uint256).max);
        items.setApprovalForAll(address(amm), true);
        vm.stopPrank();
    }

    // --- Unit Tests ---

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

        uint256 expectedLP = (1000 * 10**18) - amm.MINIMUM_LIQUIDITY();
        
        assertEq(lpMinted, expectedLP);
        assertEq(lpToken.balanceOf(alice), expectedLP);

        (uint256 resCoin, uint256 resDust, ) = amm.getReserves();
        assertEq(resCoin, coinAmount);
        assertEq(resDust, dustAmount);
    }

    function test_RemoveLiquidity() public {
        uint256 coinAmount = 10_000 * 10**18;
        uint256 dustAmount = 10_000 * 10**18;

        vm.startPrank(alice);
        uint256 lpMinted = amm.addLiquidity(coinAmount, dustAmount, 0, 0, block.timestamp + 100);
        
        lpToken.approve(address(amm), lpMinted);
        (uint256 coinOut, uint256 dustOut) = amm.removeLiquidity(lpMinted, 0, 0, block.timestamp + 100);
        vm.stopPrank();

        assertApproxEqAbs(coinOut, coinAmount, 1000); // 1000 burnt
        assertApproxEqAbs(dustOut, dustAmount, 1000);
    }

    function test_SwapCoinForDust() public {
        uint256 liqAmount = 10_000 * 10**18;
        vm.prank(alice);
        amm.addLiquidity(liqAmount, liqAmount, 0, 0, block.timestamp + 100);

        uint256 swapAmount = 100 * 10**18;
        uint256 expectedOut = amm.getAmountOut(swapAmount, liqAmount, liqAmount);
        uint256 bobDustBefore = items.balanceOf(bob, 0);

        vm.prank(bob);
        uint256 actualOut = amm.swapForgeCoinForDust(swapAmount, 0, block.timestamp + 100);

        uint256 bobDustAfter = items.balanceOf(bob, 0);
        assertEq(actualOut, expectedOut);
        assertEq(bobDustAfter - bobDustBefore, expectedOut);
    }

    function test_SwapDustForCoin() public {
        uint256 liqAmount = 10_000 * 10**18;
        vm.prank(alice);
        amm.addLiquidity(liqAmount, liqAmount, 0, 0, block.timestamp + 100);

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
        uint256 liqAmount = 10_000 * 10**18;
        vm.prank(alice);
        amm.addLiquidity(liqAmount, liqAmount, 0, 0, block.timestamp + 100);

        uint256 swapAmount = 100 * 10**18;
        uint256 expectedOut = amm.getAmountOut(swapAmount, liqAmount, liqAmount);

        vm.prank(bob);
        vm.expectRevert(ForgeAMM.SlippageExceeded.selector);
        amm.swapForgeCoinForDust(swapAmount, expectedOut + 1, block.timestamp + 100);
    }

    function test_DeadlineExpired() public {
        vm.expectRevert(ForgeAMM.DeadlineExpired.selector);
        amm.addLiquidity(100, 100, 0, 0, block.timestamp - 1);
    }

    function test_RemoveLiquidityInvalidInputs() public {
        vm.expectRevert(ForgeAMM.InsufficientLiquidityBurned.selector);
        amm.removeLiquidity(0, 0, 0, block.timestamp + 100);
    }

    function test_SwapZeroInputs() public {
        vm.expectRevert(ForgeAMM.InsufficientInputAmount.selector);
        amm.swapForgeCoinForDust(0, 0, block.timestamp + 100);

        vm.expectRevert(ForgeAMM.InsufficientInputAmount.selector);
        amm.swapDustForForgeCoin(0, 0, block.timestamp + 100);
    }

    function test_MathYulOptimizations() public pure {
        assertEq(AMMath.sqrt(144), 12);
        assertEq(AMMath.sqrt(0), 0);
        assertEq(AMMath.sqrt(3), 1);
        assertEq(AMMath.sqrt(10**36), 10**18);

        assertEq(AMMath.safeMul(5, 10), 50);
        assertEq(AMMath.safeMul(0, 100), 0);

        assertEq(AMMath.min(5, 10), 5);
    }

    // --- Fuzz Tests ---

    function testFuzz_AddLiquidity(uint256 coinAmount, uint256 dustAmount) public {
        coinAmount = bound(coinAmount, 1000 * 10**18, 500_000 * 10**18);
        dustAmount = bound(dustAmount, 1000 * 10**18, 500_000 * 10**18);

        vm.startPrank(alice);
        uint256 lpMinted = amm.addLiquidity(coinAmount, dustAmount, 0, 0, block.timestamp + 100);
        assertTrue(lpMinted > 0);
        vm.stopPrank();
    }

    function testFuzz_SwapSlippage(uint256 swapAmount) public {
        uint256 liqAmount = 100_000 * 10**18;
        vm.prank(alice);
        amm.addLiquidity(liqAmount, liqAmount, 0, 0, block.timestamp + 100);

        swapAmount = bound(swapAmount, 1 * 10**18, 5_000 * 10**18);

        vm.prank(bob);
        uint256 actualOut = amm.swapForgeCoinForDust(swapAmount, 0, block.timestamp + 100);
        assertTrue(actualOut > 0);
    }
}
