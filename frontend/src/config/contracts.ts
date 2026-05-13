import { createConfig, http } from 'wagmi';
import { localhost, baseSepolia } from 'wagmi/chains';
import { getDefaultConfig } from '@rainbow-me/rainbowkit';

// Load Addresses
import addresses from './deployments.json';

// Load ABIs
import ForgeCoinABI from './abi/ForgeCoin.json';
import ForgeItemsABI from './abi/ForgeItems.json';
import GachaLootboxABI from './abi/GachaLootbox.json';
import ForgeAMMABI from './abi/ForgeAMM.json';
import ForgeVaultABI from './abi/ForgeVault.json';
import NFTRentalVaultABI from './abi/NFTRentalVault.json';
import ForgeGovernorABI from './abi/ForgeGovernor.json';
import ForgeTimelockABI from './abi/ForgeTimelock.json';

export const config = getDefaultConfig({
  appName: 'Decentralized Forge',
  projectId: process.env.NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID || 'cd1081566497f1f7d549079fceb2053f', // Fallback to dummy Project ID
  chains: [baseSepolia, localhost],
  transports: {
    [baseSepolia.id]: http('https://base-sepolia-rpc.publicnode.com'),
    [localhost.id]: http('http://127.0.0.1:8545'),
  },
});

export const CONTRACTS = {
  ForgeCoin: {
    address: addresses.ForgeCoin as `0x${string}`,
    abi: ForgeCoinABI.abi,
  },
  ForgeItems: {
    address: addresses.ForgeItems as `0x${string}`,
    abi: ForgeItemsABI.abi,
  },
  GachaLootbox: {
    address: addresses.GachaLootbox as `0x${string}`,
    abi: GachaLootboxABI.abi,
  },
  ForgeAMM: {
    address: addresses.ForgeAMM as `0x${string}`,
    abi: ForgeAMMABI.abi,
  },
  ForgeVault: {
    address: addresses.ForgeVault as `0x${string}`,
    abi: ForgeVaultABI.abi,
  },
  NFTRentalVault: {
    address: addresses.NFTRentalVault as `0x${string}`,
    abi: NFTRentalVaultABI.abi,
  },
  ForgeGovernor: {
    address: addresses.ForgeGovernor as `0x${string}`,
    abi: ForgeGovernorABI.abi,
  },
  ForgeTimelock: {
    address: addresses.ForgeTimelock as `0x${string}`,
    abi: ForgeTimelockABI.abi,
  },
  MockVRFCoordinator: {
    address: addresses.MockVRFCoordinator as `0x${string}`,
    abi: [{
      inputs: [{ name: 'requestId', type: 'uint256' }],
      name: 'fulfillRandomWordsSimple',
      outputs: [],
      stateMutability: 'nonpayable',
      type: 'function'
    }],
  },
};
