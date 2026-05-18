# Decentralized Forge 🔨

A comprehensive GameFi ecosystem built with Solidity and Foundry.

## Setup & Installation

Чтобы развернуть этот проект на новом компьютере, выполните следующие шаги в терминале:

1. **Клонируйте репозиторий вместе со всеми зависимостями (submodules):**
   ```bash
   git clone --recurse-submodules https://github.com/d0kuzu/Forge.git
   cd Forge
   ```
   *(Если вы уже склонировали репозиторий без флага `--recurse-submodules`, подтяните библиотеки командой: `git submodule update --init --recursive`)*

2. **Установите Foundry (если еще не установлен):**
   ```bash
   curl -L https://foundry.paradigm.xyz | bash
   foundryup
   ```

3. **Скомпилируйте проект:**
   ```bash
   forge build
   ```

4. **Запустите тесты:**
   ```bash
   forge test
   ```

## Architecture

* **ForgeAMM**: Custom Automated Market Maker in highly optimized Yul assembly.
* **Tokens**: ForgeCoin (ERC20 Governance) and ForgeItems (ERC1155 Crafting).
* **GachaLootbox**: Chainlink VRF integrated random item drops.
* **Vaults**: ERC4626 staking and P2P NFT Rental Vault.
* **Guilds**: CREATE2 deterministic deterministic deployment of Guild contracts.

## Deployed Contracts (Base Sepolia) 🌐

Smart contracts are deployed on the **Base Sepolia L2 Network**. Below are the verified contract addresses with direct links to Basescan:

| Contract Name | Address | Explorer Link |
| :--- | :--- | :---: |
| **ForgeCoin (FGC)** | `0x283C4AD09Ea85e373f3FeaD5bbAef73530982f2B` | [🔍 View on Basescan](https://sepolia.basescan.org/address/0x283C4AD09Ea85e373f3FeaD5bbAef73530982f2B) |
| **ForgeItems (NFT)** | `0x1973189035B25bE7c62C3b8c39Ba3DC9784dfAB9` | [🔍 View on Basescan](https://sepolia.basescan.org/address/0x1973189035B25bE7c62C3b8c39Ba3DC9784dfAB9) |
| **GachaLootbox** | `0xAFdA7c5A6f9DC1FeaAD543bAB7Fe367AdF6CCa3E` | [🔍 View on Basescan](https://sepolia.basescan.org/address/0xAFdA7c5A6f9DC1FeaAD543bAB7Fe367AdF6CCa3E) |
| **ForgeAMM** | `0x738906eF04eFD75Ed9c38045834273ef9b138f02` | [🔍 View on Basescan](https://sepolia.basescan.org/address/0x738906eF04eFD75Ed9c38045834273ef9b138f02) |
| **ForgeLPToken** | `0xEbeEF3A031467503832a70473A9bACFc7AC636bf` | [🔍 View on Basescan](https://sepolia.basescan.org/address/0xEbeEF3A031467503832a70473A9bACFc7AC636bf) |
| **ForgeVault (Staking)** | `0x3836b97D2a4DF49e1356Cc94C61F974914CA5FFE` | [🔍 View on Basescan](https://sepolia.basescan.org/address/0x3836b97D2a4DF49e1356Cc94C61F974914CA5FFE) |
| **NFTRentalVault** | `0x0779dcc8235088352519684e2cF593f1D79954e9` | [🔍 View on Basescan](https://sepolia.basescan.org/address/0x0779dcc8235088352519684e2cF593f1D79954e9) |
| **ForgeGovernor (DAO)** | `0x1D002dd7606A3c5D02B1d78dB1F50E239b214d0e` | [🔍 View on Basescan](https://sepolia.basescan.org/address/0x1D002dd7606A3c5D02B1d78dB1F50E239b214d0e) |
| **ForgeTimelock** | `0x215412826D374116F48373FF7D9F37eE2Bc9bAD5` | [🔍 View on Basescan](https://sepolia.basescan.org/address/0x215412826D374116F48373FF7D9F37eE2Bc9bAD5) |
| **MockVRFCoordinator** | `0x34736C1A50D137236791E0f0358B7c18f2C6f7D4` | [🔍 View on Basescan](https://sepolia.basescan.org/address/0x34736C1A50D137236791E0f0358B7c18f2C6f7D4) |

