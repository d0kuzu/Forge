// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {ForgeCoin} from "../../src/tokens/ForgeCoin.sol";
import {ForgeItems} from "../../src/tokens/ForgeItems.sol";
import {ForgeAMM} from "../../src/amm/ForgeAMM.sol";
import {ForgeVault} from "../../src/vaults/ForgeVault.sol";
import {NFTRentalVault} from "../../src/vaults/NFTRentalVault.sol";
import {ForgeHandler} from "./ForgeHandler.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract ForgeInvariantTest is Test {
    ForgeCoin public coin;
    ForgeItems public items;
    ForgeAMM public amm;
    ForgeVault public vault;
    NFTRentalVault public rentalVault;
    ForgeHandler public handler;

    // Track initial k
    uint256 public lastK;

    function setUp() public {
        coin = new ForgeCoin(address(this), 0);
        coin.grantRole(coin.MINTER_ROLE(), address(this));

        items = new ForgeItems(address(coin), address(this), address(this));

        amm = new ForgeAMM(address(coin), address(items));
        vault = new ForgeVault(IERC20(address(coin)), address(this), address(0x999), 500);
        rentalVault = new NFTRentalVault(address(coin), address(items), address(this));

        vault.grantRole(vault.DISTRIBUTOR_ROLE(), address(this));

        // Deploy and target handler
        handler = new ForgeHandler(coin, items, amm, vault, rentalVault);
        
        // Grant minter and distributor roles to handler
        coin.grantRole(coin.MINTER_ROLE(), address(handler));
        items.grantRole(items.MINTER_ROLE(), address(handler));
        vault.grantRole(vault.DISTRIBUTOR_ROLE(), address(handler));

        handler.setUpHandler();

        targetContract(address(handler));
    }

    // --- Stateful Invariants ---

    /// @notice Constant product invariant (k never decreases on swap or actions)
    function invariant_constantProductK() public {
        (uint256 r0, uint256 r1, ) = amm.getReserves();
        
        if (r0 > 0 && r1 > 0) {
            uint256 currentK = r0 * r1;
            
            // k should never decrease from its last positive recorded state
            if (lastK > 0) {
                assertTrue(currentK >= lastK, "Constant product invariant k decreased!");
            }
            lastK = currentK;
        }
    }

    /// @notice Total supply conservation: Vault shares total supply matches mathematical assets scale
    function invariant_totalSupplyConservation() public view {
        uint256 supply = vault.totalSupply();
        uint256 assets = vault.totalAssets();
        
        if (supply > 0) {
            assertTrue(assets >= supply, "Vault total assets is less than total shares supply!");
        }
    }

    /// @notice Treasury accounting conservation: Vault assets are bounded by deposits + rewards
    function invariant_vaultTreasuryAccounting() public view {
        uint256 assets = vault.totalAssets();
        uint256 expectedMax = handler.totalVaultDeposits() + handler.totalVaultRewards();
        
        assertTrue(assets <= expectedMax + 10**18, "Vault assets grew beyond total deposits and rewards!");
    }

    /// @notice AMM reserves must never overflow packed bounds (uint112)
    function invariant_ammReservePacking() public view {
        (uint256 r0, uint256 r1, ) = amm.getReserves();
        assertTrue(r0 <= type(uint112).max, "Reserve0 overflowed packed uint112!");
        assertTrue(r1 <= type(uint112).max, "Reserve1 overflowed packed uint112!");
    }
}
