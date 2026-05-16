// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {ForgeCoin} from "../../src/tokens/ForgeCoin.sol";
import {ForgeItems} from "../../src/tokens/ForgeItems.sol";
import {ForgeAMM} from "../../src/amm/ForgeAMM.sol";
import {ForgeVault} from "../../src/vaults/ForgeVault.sol";
import {NFTRentalVault} from "../../src/vaults/NFTRentalVault.sol";
import {ForgeLPToken} from "../../src/amm/ForgeLPToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {DataTypes} from "../../src/libraries/DataTypes.sol";

contract ForgeHandler is Test {
    ForgeCoin public coin;
    ForgeItems public items;
    ForgeAMM public amm;
    ForgeVault public vault;
    NFTRentalVault public rentalVault;
    ForgeLPToken public lpToken;

    // Accounts
    address[] public users;
    address public currentSender;

    // Trackers
    uint256 public totalVaultDeposits;
    uint256 public totalVaultRewards;
    uint256 public totalLPMinted;

    constructor(
        ForgeCoin _coin,
        ForgeItems _items,
        ForgeAMM _amm,
        ForgeVault _vault,
        NFTRentalVault _rentalVault
    ) {
        coin = _coin;
        items = _items;
        amm = _amm;
        vault = _vault;
        rentalVault = _rentalVault;
        lpToken = _amm.lpToken();

        // Create test users
        users.push(address(0x1111));
        users.push(address(0x2222));
        users.push(address(0x3333));
    }

    function setUpHandler() external {
        // Fund and approve all users
        for (uint256 i = 0; i < users.length; i++) {
            coin.mint(users[i], 1_000_000 * 1e18);
            items.mintDust(users[i], 1_000_000 * 1e18);

            vm.startPrank(users[i]);
            coin.approve(address(amm), type(uint256).max);
            coin.approve(address(vault), type(uint256).max);
            coin.approve(address(rentalVault), type(uint256).max);
            items.setApprovalForAll(address(amm), true);
            items.setApprovalForAll(address(rentalVault), true);
            vm.stopPrank();
        }

        // Prime the vault to prevent first depositor rounding issues
        coin.mint(address(this), 10 * 1e18);
        coin.approve(address(vault), 10 * 1e18);
        vault.deposit(10 * 1e18, address(this));
        totalVaultDeposits += 10 * 1e18;
    }

    modifier useUser(uint256 userIndex) {
        currentSender = users[userIndex % users.length];
        _;
    }

    // --- AMM Actions ---

    function addLiquidityAMM(uint256 coinAmt, uint256 dustAmt, uint256 userIdx) public useUser(userIdx) {
        coinAmt = bound(coinAmt, 1000 * 1e18, 50_000 * 1e18);
        dustAmt = bound(dustAmt, 1000 * 1e18, 50_000 * 1e18);

        vm.startPrank(currentSender);
        try amm.addLiquidity(coinAmt, dustAmt, 0, 0, block.timestamp + 100) returns (uint256 lp) {
            totalLPMinted += lp;
        } catch {}
        vm.stopPrank();
    }

    function removeLiquidityAMM(uint256 lpAmt, uint256 userIdx) public useUser(userIdx) {
        uint256 bal = lpToken.balanceOf(currentSender);
        if (bal == 0) return;
        lpAmt = bound(lpAmt, 1, bal);

        vm.startPrank(currentSender);
        lpToken.approve(address(amm), lpAmt);
        try amm.removeLiquidity(lpAmt, 0, 0, block.timestamp + 100) {
            totalLPMinted -= lpAmt;
        } catch {}
        vm.stopPrank();
    }

    function swapCoinForDustAMM(uint256 coinIn, uint256 userIdx) public useUser(userIdx) {
        (uint256 r0, uint256 r1, ) = amm.getReserves();
        if (r0 < 1000 * 1e18 || r1 < 1000 * 1e18) return;

        coinIn = bound(coinIn, 1 * 1e18, r0 / 10); // max 10% of reserve to avoid skew

        vm.startPrank(currentSender);
        try amm.swapForgeCoinForDust(coinIn, 0, block.timestamp + 100) {} catch {}
        vm.stopPrank();
    }

    function swapDustForCoinAMM(uint256 dustIn, uint256 userIdx) public useUser(userIdx) {
        (uint256 r0, uint256 r1, ) = amm.getReserves();
        if (r0 < 1000 * 1e18 || r1 < 1000 * 1e18) return;

        dustIn = bound(dustIn, 1 * 1e18, r1 / 10);

        vm.startPrank(currentSender);
        try amm.swapDustForForgeCoin(dustIn, 0, block.timestamp + 100) {} catch {}
        vm.stopPrank();
    }

    // --- Vault Actions ---

    function depositToVault(uint256 amount, uint256 userIdx) public useUser(userIdx) {
        amount = bound(amount, 1e18, 50_000 * 1e18);

        vm.startPrank(currentSender);
        try vault.deposit(amount, currentSender) {
            totalVaultDeposits += amount;
        } catch {}
        vm.stopPrank();
    }

    function withdrawFromVault(uint256 shares, uint256 userIdx) public useUser(userIdx) {
        uint256 bal = vault.balanceOf(currentSender);
        if (bal == 0) return;
        shares = bound(shares, 1, bal);

        vm.startPrank(currentSender);
        try vault.redeem(shares, currentSender, currentSender) returns (uint256 assets) {
            if (totalVaultDeposits > assets) {
                totalVaultDeposits -= assets;
            } else {
                totalVaultDeposits = 0;
            }
        } catch {}
        vm.stopPrank();
    }

    function distributeRewardsToVault(uint256 amount) public {
        amount = bound(amount, 1e18, 5000 * 1e18);
        coin.mint(address(this), amount);
        coin.approve(address(vault), amount);
        try vault.distributeRewards(amount) {
            totalVaultRewards += amount;
        } catch {}
    }
}
