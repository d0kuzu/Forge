'use client';

import { useState, useEffect } from 'react';
import Image from 'next/image';
import { useAccount, useWriteContract, useWaitForTransactionReceipt, useReadContract, useWatchContractEvent } from 'wagmi';
import { CONTRACTS } from '@/config/contracts';
import { motion, AnimatePresence } from 'framer-motion';
import { parseEther, formatEther } from 'viem';

export default function GachaPage() {
  const { address, isConnected } = useAccount();
  const [mounted, setMounted] = useState(false);
  const [isOpening, setIsOpening] = useState(false);
  const [droppedItem, setDroppedItem] = useState<{ id: number, amount: number } | null>(null);
  const [pendingRequestId, setPendingRequestId] = useState<bigint | null>(null);

  // Watch for LootboxOpened event to capture the requestId
  useWatchContractEvent({
    ...CONTRACTS.GachaLootbox,
    eventName: 'LootboxOpened',
    onLogs(logs) {
      for (const log of logs) {
        const args = (log as any).args;
        if (args && args.requester === address) {
          setPendingRequestId(args.requestId);
        }
      }
    },
  });

  // Watch for LootboxFulfilled event to display the dropped item pop-up
  useWatchContractEvent({
    ...CONTRACTS.GachaLootbox,
    eventName: 'LootboxFulfilled',
    onLogs(logs) {
      for (const log of logs) {
        const args = (log as any).args;
        if (args && args.requester === address) {
          setDroppedItem({
            id: Number(args.itemId),
            amount: Number(args.amount)
          });
          setPendingRequestId(null); // Reset pending request once fulfilled!
        }
      }
    },
  });

  useEffect(() => {
    setMounted(true);
  }, []);

  const { data: hash, writeContract, isPending } = useWriteContract();
  const { isLoading: isConfirming, isSuccess: isConfirmed } = useWaitForTransactionReceipt({
    hash,
  });

  // Hook for VRF Fulfill transaction
  const { data: vrfHash, writeContract: writeVrf, isPending: isVrfPending } = useWriteContract();
  const { isLoading: isVrfConfirming, isSuccess: isVrfConfirmed } = useWaitForTransactionReceipt({
    hash: vrfHash,
  });

  const { data: allowance, refetch: refetchAllowance } = useReadContract({
    ...CONTRACTS.ForgeCoin,
    functionName: 'allowance',
    args: address ? [address, CONTRACTS.GachaLootbox.address] : undefined,
    query: {
      enabled: !!address,
      refetchInterval: 3000,
    }
  });

  const { data: lootboxConfig } = useReadContract({
    ...CONTRACTS.GachaLootbox,
    functionName: 'getLootboxConfig',
    args: [1n],
    query: {
      refetchInterval: 10000,
    }
  });

  const cost = lootboxConfig
    ? (Array.isArray(lootboxConfig)
        ? BigInt(lootboxConfig[0])
        : BigInt((lootboxConfig as any).priceInForgeCoin !== undefined ? (lootboxConfig as any).priceInForgeCoin : 0n))
    : parseEther('10');
  const needsApproval = allowance === undefined || (allowance as bigint) < cost;

  const handleAction = () => {
    if (needsApproval) {
      writeContract({
        ...CONTRACTS.ForgeCoin,
        functionName: 'approve',
        args: [CONTRACTS.GachaLootbox.address, cost * 10n], // Approve enough for 10 boxes
      });
    } else {
      writeContract({
        ...CONTRACTS.GachaLootbox,
        functionName: 'openLootbox',
        args: [1n], // Lootbox Type 1
      });
    }
  };

  const handleRevealLoot = () => {
    if (!pendingRequestId) return;
    writeVrf({
      ...CONTRACTS.MockVRFCoordinator,
      functionName: 'fulfillRandomWordsSimple',
      args: [pendingRequestId],
    });
  };

  // Refetch allowance after transaction confirms
  useEffect(() => {
    if (isConfirmed) refetchAllowance();
  }, [isConfirmed, refetchAllowance]);

  if (!mounted) return null;

  return (
    <div className="flex flex-col items-center gap-8 w-full max-w-4xl mx-auto py-12">
      <div className="text-center flex flex-col gap-4">
        <h1 className="text-4xl font-extrabold tracking-tight">
          Mystic <span className="text-transparent bg-clip-text bg-gradient-to-r from-purple-400 to-pink-500">Lootbox</span>
        </h1>
        <p className="text-zinc-400 max-w-lg">
          Try your luck and obtain rare artifacts, weapons, and magical dust. Powered by Chainlink VRF for provably fair drops.
        </p>
      </div>

      <div className="flex flex-col items-center gap-8 mt-8">
        {/* Lootbox Image with Animation */}
        <motion.div
          animate={{
            y: [0, -10, 0],
          }}
          transition={{
            duration: 4,
            repeat: Infinity,
            ease: "easeInOut",
          }}
          className="relative"
        >
          <div className="absolute inset-0 bg-purple-500/20 blur-3xl rounded-full"></div>
          <Image 
            src="/assets/lootbox.png" 
            alt="Lootbox" 
            width={300} 
            height={300} 
            className={`relative drop-shadow-[0_0_30px_rgba(192,132,252,0.6)] ${isPending || isConfirming ? 'animate-pulse' : ''}`} 
          />
        </motion.div>

        {/* Info Card */}
        <div className="bg-zinc-900 border border-zinc-800 rounded-2xl p-6 w-full max-w-md shadow-xl">
          <div className="flex justify-between items-center mb-6 border-b border-zinc-800 pb-4">
            <span className="text-zinc-400">Cost per Box</span>
            <span className="font-bold text-xl text-indigo-400">
              {parseFloat(formatEther(cost)).toFixed(0)} FGC
            </span>
          </div>

          <div className="flex flex-col gap-3 mb-6">
            <h3 className="text-sm font-semibold text-zinc-500 uppercase tracking-wider">Drop Rates</h3>
            <div className="flex justify-between items-center">
              <span className="text-zinc-300">Magical Dust (50x)</span>
              <span className="text-green-400">50%</span>
            </div>
            <div className="flex justify-between items-center">
              <span className="text-zinc-300">Iron Sword</span>
              <span className="text-blue-400">30%</span>
            </div>
            <div className="flex justify-between items-center">
              <span className="text-zinc-300">Iron Shield</span>
              <span className="text-purple-400">20%</span>
            </div>
          </div>

          <button
            onClick={handleAction}
            disabled={!mounted || !isConnected || isPending || isConfirming}
            className={`w-full py-4 rounded-xl font-bold text-lg transition-all ${
              !mounted || !isConnected 
                ? 'bg-zinc-800 text-zinc-500 cursor-not-allowed' 
                : 'bg-gradient-to-r from-indigo-500 to-purple-600 hover:from-indigo-400 hover:to-purple-500 text-white shadow-lg shadow-purple-500/25 hover:shadow-purple-500/50'
            }`}
          >
            {!mounted || !isConnected 
              ? 'Connect Wallet' 
              : isPending 
                ? 'Confirming in Wallet...' 
                : isConfirming 
                  ? 'Awaiting Confirmation...' 
                  : needsApproval 
                    ? 'Approve FGC' 
                    : 'Open Lootbox'}
          </button>
        </div>

        {/* Success / Reveal Panel */}
        {pendingRequestId && (
          <motion.div 
            initial={{ opacity: 0, scale: 0.95 }}
            animate={{ opacity: 1, scale: 1 }}
            className="bg-indigo-950/40 border border-indigo-500/30 rounded-2xl p-6 w-full max-w-md text-center shadow-xl relative overflow-hidden backdrop-blur-md"
          >
            <div className="absolute inset-0 bg-gradient-to-br from-indigo-500/10 to-purple-500/10 pointer-events-none"></div>
            
            <h3 className="text-lg font-bold text-white mb-2 flex items-center justify-center gap-2">
              <span className="animate-pulse">🔮</span> VRF Request Sent!
            </h3>
            
            <p className="text-zinc-400 text-sm mb-4">
              Lootbox request registered under ID: <span className="text-indigo-400 font-bold">#{pendingRequestId.toString()}</span>.<br/>
              Simulate the Chainlink VRF node callback directly on-screen!
            </p>

            <button
              onClick={handleRevealLoot}
              disabled={isVrfPending || isVrfConfirming}
              className={`w-full py-3 rounded-xl font-bold transition-all relative z-10 ${
                isVrfPending || isVrfConfirming
                  ? 'bg-zinc-800 text-zinc-500 cursor-not-allowed'
                  : 'bg-gradient-to-r from-purple-500 to-indigo-600 hover:from-purple-400 hover:to-indigo-500 text-white shadow-lg shadow-indigo-500/20 hover:shadow-indigo-500/40 animate-pulse'
              }`}
            >
              {isVrfPending 
                ? 'Confirming Reveal...' 
                : isVrfConfirming 
                  ? 'Revealing Loot...' 
                  : '⚡ Reveal Random Drop'}
            </button>
          </motion.div>
        )}
      </div>

      <AnimatePresence>
        {droppedItem && (
          <motion.div 
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/80 backdrop-blur-sm"
          >
            <motion.div
              initial={{ scale: 0.8, opacity: 0 }}
              animate={{ scale: 1, opacity: 1 }}
              exit={{ scale: 0.8, opacity: 0 }}
              className="bg-zinc-900 border border-zinc-800 rounded-3xl p-8 max-w-sm w-full text-center relative overflow-hidden"
            >
              <div className="absolute inset-0 bg-gradient-to-br from-indigo-500/20 to-purple-500/20 pointer-events-none"></div>
              
              <h2 className="text-3xl font-extrabold mb-6 text-transparent bg-clip-text bg-gradient-to-r from-indigo-400 to-purple-400">
                Item Dropped!
              </h2>
              
              <div className="relative w-40 h-40 mx-auto mb-6 flex items-center justify-center bg-zinc-800/50 rounded-full border border-zinc-700/50">
                <Image 
                  src={droppedItem.id === 0 ? '/assets/dust.png' : droppedItem.id === 1 ? '/assets/sword.png' : '/assets/shield.png'} 
                  alt="Dropped Item" 
                  width={120} 
                  height={120}
                  className="drop-shadow-[0_0_20px_rgba(167,139,250,0.6)]"
                />
              </div>

              <h3 className="text-xl font-bold text-white mb-2">
                {droppedItem.id === 0 ? 'Magical Dust' : droppedItem.id === 1 ? 'Iron Sword' : 'Iron Shield'}
              </h3>
              <p className="text-zinc-400 mb-8">
                Amount: <span className="text-indigo-400 font-bold">{droppedItem.amount}</span>
              </p>

              <button
                onClick={() => setDroppedItem(null)}
                className="w-full py-3 rounded-xl font-bold text-white bg-zinc-800 hover:bg-zinc-700 transition-colors relative z-10"
              >
                Awesome!
              </button>
            </motion.div>
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
}
