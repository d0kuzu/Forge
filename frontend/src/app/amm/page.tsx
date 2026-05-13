'use client';

import { useState, useEffect } from 'react';
import { useAccount, useWriteContract, useReadContract, useWaitForTransactionReceipt } from 'wagmi';
import { CONTRACTS } from '@/config/contracts';
import { ArrowDownUp } from 'lucide-react';
import { parseEther, formatEther } from 'viem';

export default function AMMPage() {
  const { address, isConnected } = useAccount();
  const [mounted, setMounted] = useState(false);
  const [isCoinToDust, setIsCoinToDust] = useState(true);
  const [amountIn, setAmountIn] = useState('');

  useEffect(() => {
    setMounted(true);
  }, []);

  const { data: hash, writeContract, isPending } = useWriteContract();
  const { isLoading: isConfirming, isSuccess: isConfirmed } = useWaitForTransactionReceipt({ hash });

  // Read Reserves
  const { data: reserves } = useReadContract({
    ...CONTRACTS.ForgeAMM,
    functionName: 'getReserves',
  }) as { data: readonly [bigint, bigint, number] | undefined };

  const reserveCoin = reserves?.[0] || 0n;
  const reserveDust = reserves?.[1] || 0n;

  // Calculate expected out based on Yul AMM logic
  let expectedOut = 0n;
  if (amountIn && !isNaN(Number(amountIn)) && Number(amountIn) > 0) {
    const amountInWei = parseEther(amountIn);
    if (isCoinToDust && reserveCoin > 0n) {
      const amountInWithFee = amountInWei * 997n;
      const numerator = amountInWithFee * reserveDust;
      const denominator = (reserveCoin * 1000n) + amountInWithFee;
      expectedOut = numerator / denominator;
    } else if (!isCoinToDust && reserveDust > 0n) {
      const amountInWithFee = amountInWei * 997n;
      const numerator = amountInWithFee * reserveCoin;
      const denominator = (reserveDust * 1000n) + amountInWithFee;
      expectedOut = numerator / denominator;
    }
  }

  // Check Approvals
  const { data: allowance } = useReadContract({
    ...CONTRACTS.ForgeCoin,
    functionName: 'allowance',
    args: address ? [address, CONTRACTS.ForgeAMM.address] : undefined,
    query: { enabled: !!address, refetchInterval: 3000 }
  });

  const { data: isApprovedForAll } = useReadContract({
    ...CONTRACTS.ForgeItems,
    functionName: 'isApprovedForAll',
    args: address ? [address, CONTRACTS.ForgeAMM.address] : undefined,
    query: { enabled: !!address, refetchInterval: 3000 }
  });

  const amountInWei = amountIn ? parseEther(amountIn) : 0n;
  const needsApproveCoin = isCoinToDust && (allowance === undefined || (allowance as bigint) < amountInWei);
  const needsApproveDust = !isCoinToDust && !isApprovedForAll;

  const handleSwap = () => {
    if (!amountIn) return;
    
    if (needsApproveCoin) {
      writeContract({
        ...CONTRACTS.ForgeCoin,
        functionName: 'approve',
        args: [CONTRACTS.ForgeAMM.address, parseEther('1000000')], // Approve large amount for UX
      });
      return;
    }

    if (needsApproveDust) {
      writeContract({
        ...CONTRACTS.ForgeItems,
        functionName: 'setApprovalForAll',
        args: [CONTRACTS.ForgeAMM.address, true],
      });
      return;
    }

    // Using 0 as minOut for simplicity, in prod we'd use expectedOut * 0.99 for 1% slippage
    if (isCoinToDust) {
      writeContract({
        ...CONTRACTS.ForgeAMM,
        functionName: 'swapForgeCoinForDust',
        args: [amountInWei, 0n, BigInt(Math.floor(Date.now() / 1000) + 3600)], // 1 hour deadline
      });
    } else {
      writeContract({
        ...CONTRACTS.ForgeAMM,
        functionName: 'swapDustForForgeCoin',
        args: [amountInWei, 0n, BigInt(Math.floor(Date.now() / 1000) + 3600)],
      });
    }
  };

  if (!mounted) return null;

  return (
    <div className="flex flex-col items-center gap-8 w-full max-w-lg mx-auto py-12">
      <div className="text-center flex flex-col gap-2">
        <h1 className="text-4xl font-extrabold tracking-tight">Swap</h1>
        <p className="text-zinc-400">Trade ForgeCoin and Magical Dust instantly.</p>
      </div>

      <div className="bg-zinc-900 border border-zinc-800 rounded-3xl p-4 w-full shadow-2xl">
        {/* Input */}
        <div className="bg-zinc-950 border border-zinc-800 rounded-2xl p-4 mb-2">
          <div className="flex justify-between mb-2">
            <span className="text-sm text-zinc-400">You pay</span>
          </div>
          <div className="flex items-center justify-between gap-4">
            <input
              type="number"
              placeholder="0.0"
              value={amountIn}
              onChange={(e) => setAmountIn(e.target.value)}
              className="bg-transparent text-4xl font-bold outline-none w-full"
            />
            <div className="bg-zinc-800 rounded-xl px-4 py-2 flex items-center gap-2">
              {isCoinToDust ? 'FGC' : 'DUST'}
            </div>
          </div>
        </div>

        {/* Swap Direction Arrow */}
        <div className="flex justify-center -my-5 relative z-10">
          <button 
            onClick={() => setIsCoinToDust(!isCoinToDust)}
            className="bg-zinc-800 border-4 border-zinc-900 p-2 rounded-xl hover:bg-zinc-700 transition-colors"
          >
            <ArrowDownUp className="w-5 h-5 text-zinc-300" />
          </button>
        </div>

        {/* Output */}
        <div className="bg-zinc-950 border border-zinc-800 rounded-2xl p-4 mt-2 mb-4">
          <div className="flex justify-between mb-2">
            <span className="text-sm text-zinc-400">You receive</span>
          </div>
          <div className="flex items-center justify-between gap-4">
            <input
              type="text"
              readOnly
              value={expectedOut > 0n ? formatEther(expectedOut) : '0.0'}
              className="bg-transparent text-4xl font-bold outline-none w-full text-zinc-500"
            />
            <div className="bg-zinc-800 rounded-xl px-4 py-2 flex items-center gap-2">
              {!isCoinToDust ? 'FGC' : 'DUST'}
            </div>
          </div>
        </div>

        {/* Details */}
        <div className="px-2 py-2 flex flex-col gap-2 mb-4 text-sm text-zinc-400">
          <div className="flex justify-between">
            <span>Exchange Rate</span>
            <span>
              1 {isCoinToDust ? 'FGC' : 'DUST'} = {
                reserveCoin > 0n && reserveDust > 0n 
                  ? (isCoinToDust ? Number(reserveDust) / Number(reserveCoin) : Number(reserveCoin) / Number(reserveDust)).toFixed(4)
                  : '0.0'
              } {!isCoinToDust ? 'FGC' : 'DUST'}
            </span>
          </div>
          <div className="flex justify-between">
            <span>Pool Fee</span>
            <span>0.3%</span>
          </div>
        </div>

        {/* Button */}
        <button
          onClick={handleSwap}
          disabled={!isConnected || isPending || isConfirming || !amountIn}
          className={`w-full py-4 rounded-xl font-bold text-lg transition-all ${
            !isConnected || !amountIn
              ? 'bg-zinc-800 text-zinc-500 cursor-not-allowed' 
              : 'bg-indigo-500 hover:bg-indigo-400 text-white shadow-lg shadow-indigo-500/25'
          }`}
        >
          {!isConnected 
            ? 'Connect Wallet' 
            : !amountIn 
              ? 'Enter an amount'
              : isPending || isConfirming
                ? 'Confirming...' 
                : needsApproveCoin 
                  ? 'Approve FGC'
                  : needsApproveDust
                    ? 'Approve Dust'
                    : 'Swap'}
        </button>
      </div>
      
      {isConfirmed && (
        <div className="text-green-400 text-sm">Swap Successful!</div>
      )}
    </div>
  );
}
