'use client';

import { useState, useEffect } from 'react';
import { useAccount, useWriteContract, useWaitForTransactionReceipt, useReadContracts } from 'wagmi';
import { CONTRACTS } from '@/config/contracts';
import Image from 'next/image';
import { formatEther } from 'viem';

export default function CraftPage() {
  const { address, isConnected } = useAccount();
  const [mounted, setMounted] = useState(false);
  const [selectedRecipe, setSelectedRecipe] = useState<0 | 1>(0);

  useEffect(() => {
    setMounted(true);
  }, []);
  const { data: hash, writeContract, isPending } = useWriteContract();
  const { isLoading: isConfirming, isSuccess: isConfirmed } = useWaitForTransactionReceipt({ hash });

  // Read Inventory (Dust:0, Sword:1, Shield:2, UpgradedShield:3, UpgradedSword:4)
  const { data: inventory } = useReadContracts({
    contracts: [
      { ...CONTRACTS.ForgeItems, functionName: 'balanceOf', args: address ? [address, 0n] : undefined },
      { ...CONTRACTS.ForgeItems, functionName: 'balanceOf', args: address ? [address, 1n] : undefined },
      { ...CONTRACTS.ForgeItems, functionName: 'balanceOf', args: address ? [address, 2n] : undefined },
      { ...CONTRACTS.ForgeItems, functionName: 'balanceOf', args: address ? [address, 3n] : undefined },
      { ...CONTRACTS.ForgeItems, functionName: 'balanceOf', args: address ? [address, 4n] : undefined },
    ],
    query: {
      enabled: !!address,
      refetchInterval: 3000,
    }
  });

  const dust = inventory?.[0].result ? Number(formatEther(inventory[0].result as bigint)) : 0;
  const swords = inventory?.[1].result ? Number(inventory[1].result) : 0;
  const shields = inventory?.[2].result ? Number(inventory[2].result) : 0;
  const upgradedShields = inventory?.[3].result ? Number(inventory[3].result) : 0;
  const upgradedSwords = inventory?.[4].result ? Number(inventory[4].result) : 0;

  const hasMaterials = selectedRecipe === 0 
    ? (dust >= 100 && shields >= 1)
    : (dust >= 100 && swords >= 1);

  const handleCraft = () => {
    writeContract({
      ...CONTRACTS.ForgeItems,
      functionName: 'craft',
      args: [BigInt(selectedRecipe)],
    });
  };

  if (!mounted) return null;

  return (
    <div className="flex flex-col items-center gap-8 w-full max-w-5xl mx-auto py-12">
      <div className="text-center flex flex-col gap-2">
        <h1 className="text-4xl font-extrabold tracking-tight">The Anvil</h1>
        <p className="text-zinc-400">Combine raw materials to craft powerful gear.</p>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 gap-8 w-full mt-8">
        
        {/* Available Recipes & Inventory */}
        <div className="flex flex-col gap-8">
          
          <div className="flex flex-col gap-4">
            <h2 className="text-xl font-bold border-b border-zinc-800 pb-2">Available Recipes</h2>
            
            {/* Recipe 0: Shield -> Upgraded Shield */}
            <div 
              onClick={() => setSelectedRecipe(0)}
              className={`border rounded-2xl p-4 flex gap-4 items-center relative overflow-hidden cursor-pointer transition-all ${
                selectedRecipe === 0 ? 'bg-indigo-500/20 border-indigo-500' : 'bg-zinc-900 border-zinc-800 hover:border-indigo-500/50'
              }`}
            >
              {selectedRecipe === 0 && <div className="absolute top-0 left-0 w-1 h-full bg-indigo-500"></div>}
              
              <div className="w-16 h-16 bg-zinc-950 rounded-lg p-2 flex items-center justify-center shrink-0">
                 <Image src="/assets/shield.png" alt="Upgraded Shield" width={50} height={50} />
              </div>
              
              <div className="flex-1">
                <h3 className={`font-bold text-lg ${selectedRecipe === 0 ? 'text-indigo-400' : 'text-zinc-300'}`}>Upgraded Shield</h3>
                <div className="text-sm text-zinc-400 flex gap-2 items-center mt-1">
                  <span className={`flex items-center gap-1 ${dust >= 100 ? 'text-green-400' : 'text-red-400'}`}>
                    <Image src="/assets/dust.png" alt="Dust" width={16} height={16} /> 100 DUST
                  </span>
                  <span>+</span>
                  <span className={`flex items-center gap-1 ${shields >= 1 ? 'text-green-400' : 'text-red-400'}`}>
                    <Image src="/assets/shield.png" alt="Shield" width={16} height={16} /> 1 Iron Shield
                  </span>
                </div>
              </div>
            </div>

            {/* Recipe 1: Sword -> Upgraded Sword */}
            <div 
              onClick={() => setSelectedRecipe(1)}
              className={`border rounded-2xl p-4 flex gap-4 items-center relative overflow-hidden cursor-pointer transition-all ${
                selectedRecipe === 1 ? 'bg-indigo-500/20 border-indigo-500' : 'bg-zinc-900 border-zinc-800 hover:border-indigo-500/50'
              }`}
            >
              {selectedRecipe === 1 && <div className="absolute top-0 left-0 w-1 h-full bg-indigo-500"></div>}
              
              <div className="w-16 h-16 bg-zinc-950 rounded-lg p-2 flex items-center justify-center shrink-0">
                 <Image src="/assets/sword.png" alt="Upgraded Sword" width={50} height={50} className="scale-110 drop-shadow-[0_0_10px_rgba(250,204,21,0.5)]" />
              </div>
              
              <div className="flex-1">
                <h3 className={`font-bold text-lg ${selectedRecipe === 1 ? 'text-indigo-400' : 'text-zinc-300'}`}>Upgraded Sword</h3>
                <div className="text-sm text-zinc-400 flex gap-2 items-center mt-1">
                  <span className={`flex items-center gap-1 ${dust >= 100 ? 'text-green-400' : 'text-red-400'}`}>
                    <Image src="/assets/dust.png" alt="Dust" width={16} height={16} /> 100 DUST
                  </span>
                  <span>+</span>
                  <span className={`flex items-center gap-1 ${swords >= 1 ? 'text-green-400' : 'text-red-400'}`}>
                    <Image src="/assets/sword.png" alt="Sword" width={16} height={16} /> 1 Iron Sword
                  </span>
                </div>
              </div>
            </div>
          </div>

          {/* Your Inventory */}
          <div className="flex flex-col gap-4">
            <h2 className="text-xl font-bold border-b border-zinc-800 pb-2">Your Inventory</h2>
            <div className="grid grid-cols-5 gap-2">
              <div className="bg-zinc-900 border border-zinc-800 rounded-xl p-2 flex flex-col items-center justify-center gap-1">
                <Image src="/assets/dust.png" alt="Dust" width={24} height={24} />
                <span className="font-bold text-sm">{dust.toFixed(0)}</span>
              </div>
              <div className="bg-zinc-900 border border-zinc-800 rounded-xl p-2 flex flex-col items-center justify-center gap-1">
                <Image src="/assets/sword.png" alt="Sword" width={24} height={24} />
                <span className="font-bold text-sm">{swords}</span>
              </div>
              <div className="bg-zinc-900 border border-zinc-800 rounded-xl p-2 flex flex-col items-center justify-center gap-1">
                <Image src="/assets/shield.png" alt="Shield" width={24} height={24} />
                <span className="font-bold text-sm">{shields}</span>
              </div>
              <div className="bg-zinc-900 border border-indigo-500/30 rounded-xl p-2 flex flex-col items-center justify-center gap-1">
                <Image src="/assets/sword.png" alt="Upgraded Sword" width={24} height={24} className="scale-110" />
                <span className="font-bold text-sm text-indigo-400">{upgradedSwords}</span>
              </div>
              <div className="bg-zinc-900 border border-indigo-500/30 rounded-xl p-2 flex flex-col items-center justify-center gap-1">
                <Image src="/assets/shield.png" alt="Upgraded Shield" width={24} height={24} />
                <span className="font-bold text-sm text-indigo-400">{upgradedShields}</span>
              </div>
            </div>
          </div>

        </div>

        {/* Crafting Interface */}
        <div className="bg-zinc-900 border border-zinc-800 rounded-3xl p-8 shadow-2xl flex flex-col items-center text-center">
          <div className="w-full flex justify-between items-center mb-8 relative">
             <div className="absolute top-1/2 left-0 w-full h-0.5 bg-zinc-800 -z-10 -translate-y-1/2"></div>
             
             <div className={`bg-zinc-950 p-2 rounded-xl border ${dust >= 100 ? 'border-green-500/50' : 'border-red-500/50'}`}>
               <Image src="/assets/dust.png" alt="Dust" width={64} height={64} />
             </div>
             
             <div className={`bg-zinc-950 p-2 rounded-xl border ${(selectedRecipe === 0 ? shields : swords) >= 1 ? 'border-green-500/50' : 'border-red-500/50'}`}>
               <Image src={selectedRecipe === 0 ? "/assets/shield.png" : "/assets/sword.png"} alt="Material" width={64} height={64} />
             </div>
             
             <div className="bg-zinc-800 text-zinc-400 rounded-full w-8 h-8 flex items-center justify-center z-10 shadow-lg">
                ➔
             </div>

             <div className="bg-zinc-950 p-2 rounded-xl border-2 border-indigo-500 shadow-[0_0_15px_rgba(99,102,241,0.5)]">
               <Image src={selectedRecipe === 0 ? "/assets/shield.png" : "/assets/sword.png"} alt="Result" width={64} height={64} className={selectedRecipe === 1 ? "scale-110 drop-shadow-[0_0_10px_rgba(250,204,21,0.5)]" : ""} />
             </div>
          </div>

          <p className="text-zinc-400 mb-6">Crafting this item will consume the required materials permanently.</p>

          <button
            onClick={handleCraft}
            disabled={!isConnected || isPending || isConfirming || !hasMaterials}
            className={`w-full py-4 rounded-xl font-bold text-lg transition-all ${
              !isConnected || !hasMaterials
                ? 'bg-zinc-800 text-zinc-500 cursor-not-allowed' 
                : 'bg-gradient-to-r from-orange-500 to-red-600 hover:from-orange-400 hover:to-red-500 text-white shadow-lg shadow-orange-500/25'
            }`}
          >
            {!isConnected 
              ? 'Connect Wallet' 
              : !hasMaterials
                ? 'Not Enough Materials'
                : isPending || isConfirming
                  ? 'Forging...' 
                  : `Forge Upgraded ${selectedRecipe === 0 ? 'Shield' : 'Sword'}`}
          </button>
          
          {isConfirmed && (
            <div className="text-green-400 text-sm mt-4">Forging Successful! Check your inventory.</div>
          )}
        </div>

      </div>
    </div>
  );
}
