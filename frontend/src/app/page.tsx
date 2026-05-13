'use client';

import { useState, useEffect } from 'react';
import Image from 'next/image';
import { useAccount, useReadContract, useReadContracts } from 'wagmi';
import { CONTRACTS } from '@/config/contracts';
import { motion } from 'framer-motion';

export default function Home() {
  const { address, isConnected } = useAccount();
  const [mounted, setMounted] = useState(false);

  useEffect(() => {
    setMounted(true);
  }, []);

  // Load Inventory (Dust:0, Sword:1, Shield:2, UpgradedShield:3, UpgradedSword:4)
  const { data: inventory } = useReadContracts({
    contracts: [
      {
        ...CONTRACTS.ForgeItems,
        functionName: 'balanceOf',
        args: [address || '0x0000000000000000000000000000000000000000', 0n],
      },
      {
        ...CONTRACTS.ForgeItems,
        functionName: 'balanceOf',
        args: [address || '0x0000000000000000000000000000000000000000', 1n],
      },
      {
        ...CONTRACTS.ForgeItems,
        functionName: 'balanceOf',
        args: [address || '0x0000000000000000000000000000000000000000', 2n],
      },
      {
        ...CONTRACTS.ForgeItems,
        functionName: 'balanceOf',
        args: [address || '0x0000000000000000000000000000000000000000', 3n],
      },
      {
        ...CONTRACTS.ForgeItems,
        functionName: 'balanceOf',
        args: [address || '0x0000000000000000000000000000000000000000', 4n],
      },
    ],
    query: {
      enabled: !!address,
      refetchInterval: 3000,
    }
  });

  const dust = inventory?.[0].result ? Number(inventory[0].result) / 10**18 : 0;
  const swords = inventory?.[1].result ? Number(inventory[1].result) : 0;
  const shields = inventory?.[2].result ? Number(inventory[2].result) : 0;
  const upgradedShields = inventory?.[3].result ? Number(inventory[3].result) : 0;
  const upgradedSwords = inventory?.[4].result ? Number(inventory[4].result) : 0;

  if (!mounted) return null;

  return (
    <div className="flex flex-col gap-8 w-full max-w-5xl mx-auto">
      {/* Header */}
      <div className="flex flex-col gap-2">
        <h1 className="text-4xl font-extrabold tracking-tight">
          Welcome to <span className="text-transparent bg-clip-text bg-gradient-to-r from-indigo-400 to-purple-400">Decentralized Forge</span>
        </h1>
        <p className="text-zinc-400 text-lg">
          Craft, trade, and battle in a fully decentralized GameFi ecosystem.
        </p>
      </div>

      {!mounted || !isConnected ? (
        <div className="bg-zinc-900/50 border border-zinc-800 rounded-2xl p-12 text-center flex flex-col items-center justify-center">
          <div className="w-16 h-16 bg-zinc-800 rounded-full flex items-center justify-center mb-4">
            <svg className="w-8 h-8 text-zinc-500" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z" />
            </svg>
          </div>
          <h2 className="text-xl font-bold mb-2">Connect Your Wallet</h2>
          <p className="text-zinc-400">Please connect your wallet to access your inventory and start playing.</p>
        </div>
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 gap-8">
          {/* Inventory Section */}
          <div className="flex flex-col gap-4">
            <h2 className="text-2xl font-bold border-b border-zinc-800 pb-2">Your Inventory</h2>
            
            <div className="grid grid-cols-2 sm:grid-cols-3 gap-4">
              
              <motion.div whileHover={{ scale: 1.05 }} className="bg-zinc-900 border border-zinc-800 rounded-xl overflow-hidden shadow-lg relative group">
                <div className="aspect-square relative p-4 bg-gradient-to-b from-zinc-800/50 to-zinc-900 flex items-center justify-center">
                  <Image src="/assets/dust.png" alt="Dust" width={100} height={100} className="drop-shadow-[0_0_15px_rgba(192,132,252,0.4)]" />
                  <div className="absolute top-2 right-2 bg-black/60 text-xs font-bold px-2 py-1 rounded-md backdrop-blur-md">
                    x{dust.toFixed(0)}
                  </div>
                </div>
                <div className="p-3 bg-zinc-900 border-t border-zinc-800">
                  <h3 className="font-bold text-sm">Magical Dust</h3>
                  <p className="text-xs text-zinc-500">Resource</p>
                </div>
              </motion.div>

              <motion.div whileHover={{ scale: 1.05 }} className="bg-zinc-900 border border-zinc-800 rounded-xl overflow-hidden shadow-lg relative group">
                <div className="aspect-square relative p-4 bg-gradient-to-b from-zinc-800/50 to-zinc-900 flex items-center justify-center">
                  <Image src="/assets/sword.png" alt="Sword" width={100} height={100} className="drop-shadow-[0_0_15px_rgba(96,165,250,0.4)]" />
                  <div className="absolute top-2 right-2 bg-black/60 text-xs font-bold px-2 py-1 rounded-md backdrop-blur-md">
                    x{swords}
                  </div>
                </div>
                <div className="p-3 bg-zinc-900 border-t border-zinc-800">
                  <h3 className="font-bold text-sm">Iron Sword</h3>
                  <p className="text-xs text-zinc-500">Common</p>
                </div>
              </motion.div>

              <motion.div whileHover={{ scale: 1.05 }} className="bg-zinc-900 border border-zinc-800 rounded-xl overflow-hidden shadow-lg relative group">
                <div className="aspect-square relative p-4 bg-gradient-to-b from-zinc-800/50 to-zinc-900 flex items-center justify-center">
                  <Image src="/assets/shield.png" alt="Shield" width={100} height={100} className="drop-shadow-[0_0_15px_rgba(250,204,21,0.4)]" />
                  <div className="absolute top-2 right-2 bg-black/60 text-xs font-bold px-2 py-1 rounded-md backdrop-blur-md">
                    x{shields}
                  </div>
                </div>
                <div className="p-3 bg-zinc-900 border-t border-zinc-800">
                  <h3 className="font-bold text-sm">Iron Shield</h3>
                  <p className="text-xs text-zinc-500">Common</p>
                </div>
              </motion.div>

              <motion.div whileHover={{ scale: 1.05 }} className="bg-zinc-900 border border-indigo-500/30 rounded-xl overflow-hidden shadow-lg relative group">
                <div className="aspect-square relative p-4 bg-gradient-to-b from-indigo-900/20 to-zinc-900 flex items-center justify-center">
                  <Image src="/assets/sword.png" alt="Upgraded Sword" width={100} height={100} className="scale-110 drop-shadow-[0_0_15px_rgba(99,102,241,0.6)]" />
                  <div className="absolute top-2 right-2 bg-indigo-500/80 text-white text-xs font-bold px-2 py-1 rounded-md backdrop-blur-md shadow-lg shadow-indigo-500/50">
                    x{upgradedSwords}
                  </div>
                </div>
                <div className="p-3 bg-zinc-900 border-t border-zinc-800">
                  <h3 className="font-bold text-sm text-indigo-400">Upgraded Sword</h3>
                  <p className="text-xs text-indigo-500/70">Uncommon Weapon</p>
                </div>
              </motion.div>

              <motion.div whileHover={{ scale: 1.05 }} className="bg-zinc-900 border border-indigo-500/30 rounded-xl overflow-hidden shadow-lg relative group">
                <div className="aspect-square relative p-4 bg-gradient-to-b from-indigo-900/20 to-zinc-900 flex items-center justify-center">
                  <Image src="/assets/shield.png" alt="Upgraded Shield" width={100} height={100} className="scale-105 drop-shadow-[0_0_15px_rgba(99,102,241,0.6)]" />
                  <div className="absolute top-2 right-2 bg-indigo-500/80 text-white text-xs font-bold px-2 py-1 rounded-md backdrop-blur-md shadow-lg shadow-indigo-500/50">
                    x{upgradedShields}
                  </div>
                </div>
                <div className="p-3 bg-zinc-900 border-t border-zinc-800">
                  <h3 className="font-bold text-sm text-indigo-400">Upgraded Shield</h3>
                  <p className="text-xs text-indigo-500/70">Uncommon Armor</p>
                </div>
              </motion.div>

            </div>
          </div>

          {/* Quick Actions */}
          <div className="flex flex-col gap-4">
            <h2 className="text-2xl font-bold border-b border-zinc-800 pb-2">Quick Actions</h2>
            <div className="grid grid-cols-1 gap-4">
              <a href="/gacha" className="flex items-center justify-between bg-zinc-900 border border-zinc-800 rounded-xl p-4 hover:border-indigo-500/50 transition-colors">
                <div className="flex items-center gap-4">
                  <div className="w-12 h-12 bg-indigo-500/20 rounded-lg flex items-center justify-center">
                    <span className="text-2xl">🎁</span>
                  </div>
                  <div>
                    <h3 className="font-bold">Open Lootbox</h3>
                    <p className="text-sm text-zinc-400">Try your luck for new items</p>
                  </div>
                </div>
                <svg className="w-5 h-5 text-zinc-500" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 5l7 7-7 7" />
                </svg>
              </a>

              <a href="/amm" className="flex items-center justify-between bg-zinc-900 border border-zinc-800 rounded-xl p-4 hover:border-purple-500/50 transition-colors">
                <div className="flex items-center gap-4">
                  <div className="w-12 h-12 bg-purple-500/20 rounded-lg flex items-center justify-center">
                    <span className="text-2xl">💱</span>
                  </div>
                  <div>
                    <h3 className="font-bold">Trade Tokens</h3>
                    <p className="text-sm text-zinc-400">Swap ForgeCoin for Dust</p>
                  </div>
                </div>
                <svg className="w-5 h-5 text-zinc-500" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 5l7 7-7 7" />
                </svg>
              </a>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
