// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {ForgeCoin} from "../../src/tokens/ForgeCoin.sol";
import {ForgeVault} from "../../src/vaults/ForgeVault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract ForgeVaultTest is Test {
    ForgeCoin public coin;
    ForgeVault public vault;

    address public admin = address(this);
    address public feeRecipient = address(0x999);
    address public alice = address(0x1111);
    address public bob = address(0x2222);

    function setUp() public {
        coin = new ForgeCoin(admin, 1_000_000 * 1e18);
        vault = new ForgeVault(IERC20(address(coin)), admin, feeRecipient, 500); // 5% fee
        vault.grantRole(vault.DISTRIBUTOR_ROLE(), admin);

        coin.transfer(alice, 10_000 * 1e18);
        coin.transfer(bob, 10_000 * 1e18);
    }

    // --- Unit Tests ---

    function test_ConstructorZeroAddressAdmin() public {
        vm.expectRevert(ForgeVault.ZeroAddress.selector);
        new ForgeVault(IERC20(address(coin)), address(0), feeRecipient, 500);
    }

    function test_ConstructorFeeTooHigh() public {
        vm.expectRevert(abi.encodeWithSelector(ForgeVault.FeeTooHigh.selector, 1001, 1000));
        new ForgeVault(IERC20(address(coin)), admin, feeRecipient, 1001);
    }

    function test_StakingAndRewards() public {
        uint256 depositAmt = 1000 * 1e18;

        vm.startPrank(alice);
        coin.approve(address(vault), depositAmt);
        vault.deposit(depositAmt, alice);
        vm.stopPrank();

        assertEq(vault.balanceOf(alice), depositAmt);
        assertEq(vault.totalAssets(), depositAmt);

        uint256 rewardAmt = 100 * 1e18;
        coin.approve(address(vault), rewardAmt);
        vault.distributeRewards(rewardAmt);

        // Performance fee = 5% of 100 = 5 Coins
        assertEq(coin.balanceOf(feeRecipient), 5 * 1e18);
        assertEq(vault.totalAssets(), depositAmt + 95 * 1e18);
        assertEq(vault.totalRewardsDistributed(), rewardAmt);

        vm.prank(alice);
        uint256 withdrawn = vault.redeem(depositAmt, alice, alice);
        assertApproxEqAbs(withdrawn, depositAmt + 95 * 1e18, 1);
    }

    function test_DistributeRewardsZeroAmount() public {
        vm.expectRevert(ForgeVault.ZeroAmount.selector);
        vault.distributeRewards(0);
    }

    function test_DistributeRewardsRoleRestricted() public {
        vm.prank(alice);
        vm.expectRevert();
        vault.distributeRewards(100 * 1e18);
    }

    function test_SetPerformanceFee() public {
        vault.setPerformanceFee(1000); // Max 10%
        assertEq(vault.performanceFee(), 1000);

        vm.expectRevert(abi.encodeWithSelector(ForgeVault.FeeTooHigh.selector, 1001, 1000));
        vault.setPerformanceFee(1001);
    }

    function test_SetFeeRecipient() public {
        vault.setFeeRecipient(bob);
        assertEq(vault.feeRecipient(), bob);
    }

    function test_Decimals() public view {
        assertEq(vault.decimals(), 18);
    }

    // --- Fuzz Tests ---

    function testFuzz_DepositWithdraw(uint256 amount) public {
        // Prime the vault with some seed capital to prevent first depositor rounding anomalies
        coin.approve(address(vault), 10 * 1e18);
        vault.deposit(10 * 1e18, admin);

        amount = bound(amount, 1 * 1e18, 100_000 * 1e18);

        coin.mint(alice, amount);
        vm.startPrank(alice);
        coin.approve(address(vault), amount);
        uint256 shares = vault.deposit(amount, alice);
        
        uint256 withdrawn = vault.redeem(shares, alice, alice);
        assertApproxEqAbs(withdrawn, amount, 1000); // Bound by minor ERC4626 rounding
        vm.stopPrank();
    }

    function testFuzz_Rewards(uint256 rewardAmount) public {
        rewardAmount = bound(rewardAmount, 1 * 1e18, 50_000 * 1e18);

        uint256 feeBefore = coin.balanceOf(feeRecipient);
        
        coin.approve(address(vault), rewardAmount);
        vault.distributeRewards(rewardAmount);

        uint256 expectedFee = (rewardAmount * vault.performanceFee()) / vault.BPS_DENOMINATOR();
        assertEq(coin.balanceOf(feeRecipient) - feeBefore, expectedFee);
    }
}
