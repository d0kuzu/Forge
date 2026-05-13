// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {ForgeCoin} from "../src/tokens/ForgeCoin.sol";
import {ForgeVault} from "../src/vaults/ForgeVault.sol";
import {GachaLootbox} from "../src/gacha/GachaLootbox.sol";
import {NFTRentalVault} from "../src/vaults/NFTRentalVault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract RedeployVaultScript is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envOr("PRIVATE_KEY", uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80));
        address deployer = vm.addr(deployerPrivateKey);
        console2.log("Running RedeployVault with address:", deployer);

        // Deployed Addresses
        address coinAddress = 0x18F3A6035db1072c74269b899cEe27b85C224c03;
        address gachaAddress = 0x48CBc8180Fc05216B18C54b5340927C77179A6F2;
        address rentalAddress = 0x11fB3e01c0B0702a60F0D1f57814Eb1e96281416;

        ForgeCoin coin = ForgeCoin(coinAddress);
        GachaLootbox gacha = GachaLootbox(payable(gachaAddress));
        NFTRentalVault rentalVault = NFTRentalVault(rentalAddress);

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy new ForgeVault
        ForgeVault newVault = new ForgeVault(
            IERC20(coinAddress),
            deployer,
            deployer,
            500 // 5% fee
        );
        console2.log("New ForgeVault deployed at:", address(newVault));

        // 2. Mint and perform first deposit (1 FGC) to establish initial share rate
        coin.mint(deployer, 1 * 10**18);
        coin.approve(address(newVault), 1 * 10**18);
        newVault.deposit(1 * 10**18, deployer);
        console2.log("Vault seeded with 1 FGC. Shares minted.");

        // 3. Grant DISTRIBUTOR_ROLE on new vault
        newVault.grantRole(newVault.DISTRIBUTOR_ROLE(), gachaAddress);
        newVault.grantRole(newVault.DISTRIBUTOR_ROLE(), rentalAddress);
        console2.log("Distributor roles granted.");

        // 4. Update vault address on Gacha & RentalVault contracts
        gacha.setForgeVault(address(newVault));
        rentalVault.setForgeVault(address(newVault));
        console2.log("Vault address updated on Gacha and RentalVault.");

        vm.stopBroadcast();
        console2.log("RedeployVault completed successfully!");
    }
}
