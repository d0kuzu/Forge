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
