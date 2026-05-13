// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {ForgeCoin} from "../src/tokens/ForgeCoin.sol";
import {ForgeItems} from "../src/tokens/ForgeItems.sol";
import {GachaLootbox} from "../src/gacha/GachaLootbox.sol";
import {MockVRFCoordinator} from "../test/mocks/MockVRFCoordinator.sol";
import {ForgeAMM} from "../src/amm/ForgeAMM.sol";
import {ForgeVault} from "../src/vaults/ForgeVault.sol";
import {NFTRentalVault} from "../src/vaults/NFTRentalVault.sol";
import {ForgeTimelock} from "../src/governance/ForgeTimelock.sol";
import {ForgeGovernor} from "../src/governance/ForgeGovernor.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {DataTypes} from "../src/libraries/DataTypes.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";

contract DeployScript is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envOr("PRIVATE_KEY", uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80));
        address deployer = vm.addr(deployerPrivateKey);
        console2.log("Deploying contracts with address:", deployer);

        vm.startBroadcast(deployerPrivateKey);

        // 1. Tokens
        ForgeCoin coin = new ForgeCoin(deployer, 1_000_000 * 10**18);
        ForgeItems items = new ForgeItems(address(coin), deployer, deployer);
        items.setURI("https://api.forge.com/items/");

        // 2. Mock VRF
        MockVRFCoordinator vrfMock = new MockVRFCoordinator();

        // 3. GachaLootbox
        GachaLootbox gachaImpl = new GachaLootbox();
        bytes memory initData = abi.encodeWithSelector(
            GachaLootbox.initialize.selector,
            deployer,
            address(coin),
            address(items),
            address(vrfMock),
            1, // subId
            bytes32(0), // keyHash
            100000, // gasLimit
            3, // confirmations
            50 // DUST_DROP_AMOUNT
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(gachaImpl), initData);
        GachaLootbox gacha = GachaLootbox(address(proxy));

        // 4. AMM
        ForgeAMM amm = new ForgeAMM(address(coin), address(items));

        // 5. Vaults
        ForgeVault stakingVault = new ForgeVault(IERC20(address(coin)), deployer, deployer, 500); // 5% fee
        coin.approve(address(stakingVault), 10 * 10**18);
        stakingVault.deposit(10 * 10**18, deployer);
        NFTRentalVault rentalVault = new NFTRentalVault(address(coin), address(items), deployer);

        // 6. DAO
        address[] memory proposers = new address[](1);
        proposers[0] = deployer;
        address[] memory executors = new address[](1);
        executors[0] = deployer;
        
        ForgeTimelock timelock = new ForgeTimelock(0, proposers, executors, deployer);
        ForgeGovernor governor = new ForgeGovernor(IVotes(address(coin)), timelock, 0, 50, 1000 * 10**18, 4);

        // Grant Timelock roles to the Governor contract
        bytes32 PROPOSER_ROLE = keccak256("PROPOSER_ROLE");
        bytes32 EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");
        bytes32 CANCELLER_ROLE = keccak256("CANCELLER_ROLE");

        timelock.grantRole(PROPOSER_ROLE, address(governor));
        timelock.grantRole(EXECUTOR_ROLE, address(governor));
        timelock.grantRole(CANCELLER_ROLE, address(governor));

        // --- Basic Setup ---
        coin.grantRole(coin.MINTER_ROLE(), deployer);
        items.grantRole(items.MINTER_ROLE(), deployer);
        items.grantRole(items.MINTER_ROLE(), address(gacha));

        // Grant core contract roles to the Timelock Controller so the DAO can execute proposals
        bytes32 DEFAULT_ADMIN_ROLE = 0x00;
        bytes32 GAME_ADMIN_ROLE = keccak256("GAME_ADMIN_ROLE");

        gacha.grantRole(GAME_ADMIN_ROLE, address(timelock));
        gacha.grantRole(DEFAULT_ADMIN_ROLE, address(timelock));
        coin.grantRole(DEFAULT_ADMIN_ROLE, address(timelock));
        items.grantRole(DEFAULT_ADMIN_ROLE, address(timelock));
        stakingVault.grantRole(DEFAULT_ADMIN_ROLE, address(timelock));

        items.defineItem(1, "Sword", DataTypes.Rarity.Common, 0, false);
        items.defineItem(2, "Shield", DataTypes.Rarity.Common, 0, false);

        uint256[] memory ids = new uint256[](3);
        ids[0] = 1; ids[1] = 2; ids[2] = 0;
        uint256[] memory weights = new uint256[](3);
        weights[0] = 30; weights[1] = 20; weights[2] = 50;
        gacha.configureLootbox(1, 10 * 10**18, ids, weights);

        // Mint initial dust to AMM deployer to provide liquidity later
        items.mintDust(deployer, 100_000 * 10**18);

        // --- Provide AMM Liquidity (10k FGC and 10k Dust) ---
        coin.approve(address(amm), 10_000 * 10**18);
        items.setApprovalForAll(address(amm), true);
        amm.addLiquidity(
            10_000 * 10**18, // FGC desired
            10_000 * 10**18, // Dust desired
            10_000 * 10**18, // FGC min
            10_000 * 10**18, // Dust min
            block.timestamp + 600
        );

        // --- Fund Test Accounts with 10k FGC and 10k Dust each (Local only) ---
        if (block.chainid == 31337) {
            address account1 = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;
            address account2 = 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC;

            coin.transfer(account1, 10_000 * 10**18);
            items.mintDust(account1, 10_000 * 10**18);

            coin.transfer(account2, 10_000 * 10**18);
            items.mintDust(account2, 10_000 * 10**18);
        }

        // --- Setup Fee Sweeping ---
        stakingVault.grantRole(stakingVault.DISTRIBUTOR_ROLE(), address(gacha));
        stakingVault.grantRole(stakingVault.DISTRIBUTOR_ROLE(), address(rentalVault));
        gacha.setForgeVault(address(stakingVault));
        rentalVault.setForgeVault(address(stakingVault));
        rentalVault.transferOwnership(address(timelock));

        vm.stopBroadcast();

        // Export Addresses to JSON
        string memory json = "{}";
        json = vm.serializeAddress("deployments", "ForgeCoin", address(coin));
        json = vm.serializeAddress("deployments", "ForgeItems", address(items));
        json = vm.serializeAddress("deployments", "MockVRFCoordinator", address(vrfMock));
        json = vm.serializeAddress("deployments", "GachaLootbox", address(gacha));
        json = vm.serializeAddress("deployments", "ForgeAMM", address(amm));
        json = vm.serializeAddress("deployments", "ForgeLPToken", address(amm.lpToken()));
        json = vm.serializeAddress("deployments", "ForgeVault", address(stakingVault));
        json = vm.serializeAddress("deployments", "NFTRentalVault", address(rentalVault));
        json = vm.serializeAddress("deployments", "ForgeTimelock", address(timelock));
        string memory finalJson = vm.serializeAddress("deployments", "ForgeGovernor", address(governor));
        
        // Write to root, frontend will pick it up
        vm.writeJson(finalJson, "./deployments.json");

        console2.log("Deployment complete! Addresses saved to deployments.json");
    }
}
