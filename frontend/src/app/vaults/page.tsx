'use client';

import { useState, useEffect } from 'react';
import { useAccount, useWriteContract, useReadContracts, useReadContract, useWaitForTransactionReceipt } from 'wagmi';
import { CONTRACTS } from '@/config/contracts';
import { formatEther, parseEther } from 'viem';
import Image from 'next/image';

export default function VaultsPage() {
  const { address, isConnected } = useAccount();
  
  // Staking State
  const [amount, setAmount] = useState('');
  const [mounted, setMounted] = useState(false);
  const [activeTab, setActiveTab] = useState<'stake' | 'withdraw'>('stake');

  // Rental State
  const [isListingModalOpen, setIsListingModalOpen] = useState(false);
  const [selectedItemId, setSelectedItemId] = useState<number>(1); // 1: Sword, 2: Shield, 3: Upgraded Shield, 4: Upgraded Sword
  const [pricePerDay, setPricePerDay] = useState('');

  useEffect(() => {
    setMounted(true);
  }, []);

  const { data: hash, writeContract, isPending } = useWriteContract();
  const { isLoading: isConfirming, isSuccess: isConfirmed } = useWaitForTransactionReceipt({ hash });

  // Read Vault Data
  const { data: vaultData } = useReadContracts({
    contracts: [
      { ...CONTRACTS.ForgeVault, functionName: 'totalAssets' },
      { ...CONTRACTS.ForgeVault, functionName: 'totalSupply' },
      { ...CONTRACTS.ForgeVault, functionName: 'balanceOf', args: address ? [address] : undefined },
      { ...CONTRACTS.ForgeCoin, functionName: 'allowance', args: address ? [address, CONTRACTS.ForgeVault.address] : undefined },
      { ...CONTRACTS.ForgeCoin, functionName: 'balanceOf', args: address ? [address] : undefined },
    ],
    query: { refetchInterval: 3000 }
  });

  const totalAssets = vaultData?.[0].result ? (vaultData[0].result as bigint) : 0n;
  const totalSupply = vaultData?.[1].result ? (vaultData[1].result as bigint) : 0n;
  const userShares = vaultData?.[2].result ? (vaultData[2].result as bigint) : 0n;
  const allowance = vaultData?.[3].result ? (vaultData[3].result as bigint) : 0n;
  const userFGC = vaultData?.[4].result ? (vaultData[4].result as bigint) : 0n;

  // Calculate Exchange Rate: 1 vFGC = ? FGC
  const exchangeRate = totalSupply > 0n 
    ? Number(formatEther(totalAssets)) / Number(formatEther(totalSupply)) 
    : 1;

  const userFgcValue = Number(formatEther(userShares)) * exchangeRate;

  const amountInWei = amount ? parseEther(amount) : 0n;
  const needsApprove = activeTab === 'stake' && allowance < amountInWei;

  const handleAction = () => {
    if (!amount) return;

    if (activeTab === 'stake') {
      if (needsApprove) {
        writeContract({
          ...CONTRACTS.ForgeCoin,
          functionName: 'approve',
          args: [CONTRACTS.ForgeVault.address, parseEther('1000000')], // Approve large amount
        });
        return;
      }
      writeContract({
        ...CONTRACTS.ForgeVault,
        functionName: 'deposit',
        args: [amountInWei, address as `0x${string}`],
      });
    } else {
      // Withdraw (Redeem shares for assets)
      writeContract({
        ...CONTRACTS.ForgeVault,
        functionName: 'redeem',
        args: [amountInWei, address as `0x${string}`, address as `0x${string}`],
      });
    }
  };

  // --- RENTAL LOGIC ---

  // Read Rental Vault Data
  const { data: rentalData } = useReadContracts({
    contracts: [
      { ...CONTRACTS.ForgeItems, functionName: 'isApprovedForAll', args: address ? [address, CONTRACTS.NFTRentalVault.address] : undefined },
      { ...CONTRACTS.ForgeItems, functionName: 'balanceOf', args: address ? [address, BigInt(selectedItemId)] : undefined },
      { ...CONTRACTS.NFTRentalVault, functionName: 'getListing', args: [1n] },
      { ...CONTRACTS.NFTRentalVault, functionName: 'getListing', args: [2n] },
      { ...CONTRACTS.NFTRentalVault, functionName: 'getListing', args: [3n] },
      { ...CONTRACTS.NFTRentalVault, functionName: 'getListing', args: [4n] },
      { ...CONTRACTS.NFTRentalVault, functionName: 'getListing', args: [5n] },
      { ...CONTRACTS.NFTRentalVault, functionName: 'activeRentalForListing', args: [1n] },
      { ...CONTRACTS.NFTRentalVault, functionName: 'activeRentalForListing', args: [2n] },
      { ...CONTRACTS.NFTRentalVault, functionName: 'activeRentalForListing', args: [3n] },
      { ...CONTRACTS.NFTRentalVault, functionName: 'activeRentalForListing', args: [4n] },
      { ...CONTRACTS.NFTRentalVault, functionName: 'activeRentalForListing', args: [5n] },
      { ...CONTRACTS.ForgeCoin, functionName: 'allowance', args: address ? [address, CONTRACTS.NFTRentalVault.address] : undefined },
    ],
    query: { refetchInterval: 3000 }
  });

  const isItemsApproved = rentalData?.[0].result as boolean | undefined;
  const selectedItemBalance = rentalData?.[1].result ? Number(rentalData[1].result) : 0;
  
  const listings = [
    { id: 1, data: rentalData?.[2].result as any, activeRental: rentalData?.[7].result as bigint },
    { id: 2, data: rentalData?.[3].result as any, activeRental: rentalData?.[8].result as bigint },
    { id: 3, data: rentalData?.[4].result as any, activeRental: rentalData?.[9].result as bigint },
    { id: 4, data: rentalData?.[5].result as any, activeRental: rentalData?.[10].result as bigint },
    { id: 5, data: rentalData?.[6].result as any, activeRental: rentalData?.[11].result as bigint },
  ].filter(l => l.data && l.data.active);

  const rentalCoinAllowance = rentalData?.[12].result as bigint | undefined;

  const handleList = () => {
    if (!pricePerDay) return;
    if (!isItemsApproved) {
      writeContract({
        ...CONTRACTS.ForgeItems,
        functionName: 'setApprovalForAll',
        args: [CONTRACTS.NFTRentalVault.address, true],
      });
      return;
    }

    // List item (itemId, amount: 1, pricePerDay, minDuration: 1 day, maxDuration: 7 days)
    writeContract({
      ...CONTRACTS.NFTRentalVault,
      functionName: 'listItem',
      args: [BigInt(selectedItemId), 1n, parseEther(pricePerDay), BigInt(1 * 86400), BigInt(7 * 86400)],
    });
  };

  const handleRent = (listingId: number, pricePerDayWei: bigint) => {
    const rentCost = pricePerDayWei; // Assuming 1 day rent for simplicity MVP
    if (rentalCoinAllowance === undefined || rentalCoinAllowance < rentCost) {
      writeContract({
        ...CONTRACTS.ForgeCoin,
        functionName: 'approve',
        args: [CONTRACTS.NFTRentalVault.address, parseEther('100000')],
      });
      return;
    }

    writeContract({
      ...CONTRACTS.NFTRentalVault,
      functionName: 'rentItem',
      args: [BigInt(listingId), BigInt(1 * 86400)], // Rent for exactly 1 day
    });
  };

  // --- FEE SWEEPING ---
  const { data: feeData } = useReadContracts({
    contracts: [
      { ...CONTRACTS.ForgeCoin, functionName: 'balanceOf', args: [CONTRACTS.GachaLootbox.address] },
      { ...CONTRACTS.NFTRentalVault, functionName: 'accumulatedPlatformFees' },
    ],
    query: { refetchInterval: 3000 }
  });
  const gachaPendingFees = feeData?.[0].result ? (feeData[0].result as bigint) : 0n;
  const rentalPendingFees = feeData?.[1].result ? (feeData[1].result as bigint) : 0n;
  const totalPendingFees = gachaPendingFees + rentalPendingFees;

  const handleSweepGacha = () => writeContract({ ...CONTRACTS.GachaLootbox, functionName: 'sweepRevenue' });
  const handleSweepRental = () => writeContract({ ...CONTRACTS.NFTRentalVault, functionName: 'sweepPlatformFees' });

  if (!mounted) return null;

  return (
    <div className="flex flex-col items-center gap-12 w-full max-w-6xl mx-auto py-12">
      <div className="text-center flex flex-col gap-2">
        <h1 className="text-4xl font-extrabold tracking-tight">Vaults</h1>
        <p className="text-zinc-400">Stake your ForgeCoin for yields or rent NFT items.</p>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-8 w-full">
        {/* Staking Vault */}
        <div className="bg-zinc-900 border border-zinc-800 rounded-3xl p-8 shadow-xl flex flex-col">
          <div className="flex items-center gap-4 mb-6">
             <div className="w-12 h-12 bg-indigo-500/20 rounded-xl flex items-center justify-center text-2xl">
               🏦
             </div>
             <div>
               <h2 className="text-2xl font-bold">ForgeCoin Staking</h2>
               <p className="text-zinc-400 text-sm">Earn protocol fees by staking FGC</p>
             </div>
          </div>

          <div className="grid grid-cols-2 gap-4 mb-8">
            <div className="bg-zinc-950 border border-zinc-800 p-4 rounded-xl flex flex-col justify-center">
              <span className="text-sm text-zinc-500 block mb-1">Your Staked Balance</span>
              <div className="flex items-baseline gap-2">
                <span className="text-2xl font-bold text-indigo-400">
                  {parseFloat(formatEther(userShares)).toFixed(2)} vFGC
                </span>
                <span className="text-sm text-green-400 font-bold">
                  ≈ {userFgcValue.toFixed(2)} FGC
                </span>
              </div>
            </div>
            <div className="bg-zinc-950 border border-zinc-800 p-4 rounded-xl flex flex-col justify-center">
              <span className="text-sm text-zinc-500 block mb-1">Current Exchange Rate</span>
              <span className="text-2xl font-bold text-green-400">
                1 vFGC = {exchangeRate.toFixed(3)} FGC
              </span>
            </div>
          </div>

          <div className="flex flex-col gap-4 mb-4">
            {/* Tabs */}
            <div className="flex w-full bg-zinc-950 p-1 rounded-xl border border-zinc-800">
              <button
                onClick={() => { setActiveTab('stake'); setAmount(''); }}
                className={`flex-1 py-2 font-bold rounded-lg transition-all ${activeTab === 'stake' ? 'bg-indigo-500 text-white shadow' : 'text-zinc-500 hover:text-zinc-300'}`}
              >
                Stake
              </button>
              <button
                onClick={() => { setActiveTab('withdraw'); setAmount(''); }}
                className={`flex-1 py-2 font-bold rounded-lg transition-all ${activeTab === 'withdraw' ? 'bg-zinc-800 text-white shadow' : 'text-zinc-500 hover:text-zinc-300'}`}
              >
                Withdraw
              </button>
            </div>

            <div className="bg-zinc-950 border border-zinc-800 rounded-2xl p-4">
              <div className="flex justify-between mb-2">
                <span className="text-sm text-zinc-400">{activeTab === 'stake' ? 'Amount to Stake' : 'Amount of vFGC to Redeem'}</span>
                <span className="text-sm text-indigo-400 cursor-pointer" onClick={() => setAmount(formatEther(activeTab === 'stake' ? userFGC : userShares))}>
                  Max: {parseFloat(formatEther(activeTab === 'stake' ? userFGC : userShares)).toFixed(2)}
                </span>
              </div>
              <div className="flex items-center justify-between gap-4">
                <input
                  type="number"
                  placeholder="0.0"
                  value={amount}
                  onChange={(e) => setAmount(e.target.value)}
                  className="bg-transparent text-3xl font-bold outline-none w-full"
                />
                <span className="font-bold text-zinc-300">{activeTab === 'stake' ? 'FGC' : 'vFGC'}</span>
              </div>
            </div>
          </div>

          <button
            onClick={handleAction}
            disabled={!isConnected || isPending || isConfirming || !amount}
            className={`w-full py-4 rounded-xl font-bold text-lg transition-all mt-auto ${
              !isConnected || !amount
                ? 'bg-zinc-800 text-zinc-500 cursor-not-allowed' 
                : activeTab === 'stake' ? 'bg-indigo-500 hover:bg-indigo-400 text-white shadow-lg shadow-indigo-500/25' : 'bg-red-500 hover:bg-red-400 text-white shadow-lg shadow-red-500/25'
            }`}
          >
            {!isConnected 
              ? 'Connect Wallet' 
              : !amount 
                ? 'Enter an amount'
                : isPending || isConfirming
                  ? 'Confirming...' 
                  : needsApprove
                    ? 'Approve FGC'
                    : activeTab === 'stake' ? 'Stake FGC' : 'Withdraw FGC'}
          </button>
          
          {isConfirmed && (
            <div className="text-green-400 text-sm mt-4 text-center">Transaction Successful!</div>
          )}

          {/* Protocol Fee Sweep Section */}
          {totalPendingFees > 0n && (
            <div className="mt-4 p-4 bg-amber-500/10 border border-amber-500/20 rounded-xl">
              <div className="flex items-center justify-between mb-3">
                <div>
                  <span className="text-sm font-bold text-amber-400">🔄 Pending Protocol Fees</span>
                  <p className="text-xs text-zinc-500 mt-0.5">Sweep fees to Vault to boost staker yields</p>
                </div>
                <span className="text-amber-400 font-bold">{parseFloat(formatEther(totalPendingFees)).toFixed(2)} FGC</span>
              </div>
              <div className="flex gap-2">
                {gachaPendingFees > 0n && (
                  <button
                    onClick={handleSweepGacha}
                    disabled={isPending || isConfirming}
                    className="flex-1 py-2 bg-amber-500/20 hover:bg-amber-500/30 text-amber-400 border border-amber-500/30 rounded-lg text-xs font-bold transition-colors"
                  >
                    Sweep Gacha ({parseFloat(formatEther(gachaPendingFees)).toFixed(2)} FGC)
                  </button>
                )}
                {rentalPendingFees > 0n && (
                  <button
                    onClick={handleSweepRental}
                    disabled={isPending || isConfirming}
                    className="flex-1 py-2 bg-amber-500/20 hover:bg-amber-500/30 text-amber-400 border border-amber-500/30 rounded-lg text-xs font-bold transition-colors"
                  >
                    Sweep Rental ({parseFloat(formatEther(rentalPendingFees)).toFixed(2)} FGC)
                  </button>
                )}
              </div>
            </div>
          )}
        </div>

        {/* NFT Rental Vault */}
        <div className="bg-zinc-900 border border-zinc-800 rounded-3xl p-8 shadow-xl flex flex-col relative overflow-hidden">
          <div className="flex items-center justify-between mb-6">
             <div className="flex items-center gap-4">
               <div className="w-12 h-12 bg-purple-500/20 rounded-xl flex items-center justify-center text-2xl">
                 ⚔️
               </div>
               <div>
                 <h2 className="text-2xl font-bold">Equipment Rental</h2>
                 <p className="text-zinc-400 text-sm">Rent items for quests and battles</p>
               </div>
             </div>
             
             <button
               onClick={() => setIsListingModalOpen(!isListingModalOpen)}
               className="bg-purple-500/10 hover:bg-purple-500/20 text-purple-400 border border-purple-500/30 px-4 py-2 rounded-lg font-bold text-sm transition-colors"
             >
               {isListingModalOpen ? 'Close' : 'List an Item'}
             </button>
          </div>

          {/* Listing Modal Overlay */}
          {isListingModalOpen && (
            <div className="absolute inset-0 bg-zinc-950/95 z-10 p-8 flex flex-col backdrop-blur-sm border-t border-purple-500/30">
              <h3 className="text-xl font-bold mb-4 text-purple-400">Create a Listing</h3>
              
              <div className="flex flex-col gap-4">
                <div className="bg-zinc-900 border border-zinc-800 p-4 rounded-xl">
                  <label className="text-sm text-zinc-400 block mb-2">Select Item to List</label>
                  <select 
                    value={selectedItemId}
                    onChange={(e) => setSelectedItemId(Number(e.target.value))}
                    className="w-full bg-zinc-950 border border-zinc-800 rounded-lg p-3 text-white outline-none focus:border-purple-500"
                  >
                    <option value={1}>Iron Sword (ID: 1)</option>
                    <option value={2}>Iron Shield (ID: 2)</option>
                    <option value={3}>Upgraded Shield (ID: 3)</option>
                    <option value={4}>Upgraded Sword (ID: 4)</option>
                  </select>
                  <p className="text-xs text-zinc-500 mt-2">You own: {selectedItemBalance}</p>
                </div>

                <div className="bg-zinc-900 border border-zinc-800 p-4 rounded-xl">
                  <label className="text-sm text-zinc-400 block mb-2">Price per day (FGC)</label>
                  <input
                    type="number"
                    placeholder="10.0"
                    value={pricePerDay}
                    onChange={(e) => setPricePerDay(e.target.value)}
                    className="w-full bg-zinc-950 border border-zinc-800 rounded-lg p-3 text-white outline-none focus:border-purple-500"
                  />
                </div>

                <button
                  onClick={handleList}
                  disabled={!isConnected || isPending || isConfirming || !pricePerDay || selectedItemBalance === 0}
                  className={`w-full py-4 rounded-xl font-bold text-lg mt-auto transition-all ${
                    !isConnected || !pricePerDay || selectedItemBalance === 0
                      ? 'bg-zinc-800 text-zinc-500 cursor-not-allowed'
                      : 'bg-purple-500 hover:bg-purple-400 text-white shadow-lg shadow-purple-500/25'
                  }`}
                >
                  {!isConnected ? 'Connect Wallet' 
                    : selectedItemBalance === 0 ? 'You do not own this item'
                    : isPending || isConfirming ? 'Processing...'
                    : !isItemsApproved ? 'Approve NFT Transfer'
                    : 'List Item'}
                </button>
                <button onClick={() => setIsListingModalOpen(false)} className="text-zinc-500 hover:text-white mt-2">Cancel</button>
              </div>
            </div>
          )}

          {/* Marketplace Grid */}
          {!isListingModalOpen && (
            <div className="flex-1 flex flex-col">
              {listings.length === 0 ? (
                <div className="flex-1 flex flex-col items-center justify-center text-center py-12 border-2 border-dashed border-zinc-800 rounded-2xl bg-zinc-950/50">
                  <span className="text-4xl mb-4">🏪</span>
                  <h3 className="text-xl font-bold mb-2">Marketplace Empty</h3>
                  <p className="text-zinc-500 max-w-xs">
                    There are currently no items listed for rent. Check back later or list your own items!
                  </p>
                </div>
              ) : (
                <div className="grid grid-cols-1 gap-4 overflow-y-auto max-h-[400px] pr-2">
                  {listings.map((listing) => {
                    const itemId = Number(listing.data.itemId);
                    const isRented = listing.activeRental > 0n;
                    const price = parseFloat(formatEther(listing.data.pricePerDay));
                    const isOwner = listing.data.owner.toLowerCase() === address?.toLowerCase();
                    
                    return (
                      <div key={listing.id} className="bg-zinc-950 border border-zinc-800 p-4 rounded-xl flex items-center justify-between">
                        <div className="flex items-center gap-4">
                          <div className={`w-16 h-16 rounded-lg flex items-center justify-center p-2 bg-zinc-900 border ${itemId > 2 ? 'border-indigo-500/50' : 'border-zinc-800'}`}>
                            <Image 
                              src={itemId === 1 || itemId === 4 ? "/assets/sword.png" : "/assets/shield.png"} 
                              alt="Item" 
                              width={40} height={40} 
                            />
                          </div>
                          <div>
                            <h4 className={`font-bold ${itemId > 2 ? 'text-indigo-400' : 'text-zinc-300'}`}>
                              {itemId === 1 ? 'Iron Sword' : itemId === 2 ? 'Iron Shield' : itemId === 3 ? 'Upgraded Shield' : 'Upgraded Sword'}
                            </h4>
                            <p className="text-sm text-zinc-500">Lot #{listing.id}</p>
                          </div>
                        </div>
                        
                        <div className="flex flex-col items-end gap-2">
                          <div className="text-right">
                            <span className="font-bold text-green-400">{price} FGC</span>
                            <span className="text-xs text-zinc-500 block">per day</span>
                          </div>
                          <button
                            onClick={() => handleRent(listing.id, listing.data.pricePerDay)}
                            disabled={isRented || isOwner || isPending || isConfirming}
                            className={`px-4 py-2 rounded-lg text-sm font-bold ${
                              isRented || isOwner
                                ? 'bg-zinc-800 text-zinc-600 cursor-not-allowed' 
                                : 'bg-purple-500/20 text-purple-400 hover:bg-purple-500/30 border border-purple-500/50'
                            }`}
                          >
                            {isOwner ? 'Your Listing' : isRented ? 'Currently Rented' : (rentalCoinAllowance !== undefined && rentalCoinAllowance < listing.data.pricePerDay) ? 'Approve to Rent' : 'Rent (1 Day)'}
                          </button>
                        </div>
                      </div>
                    );
                  })}
                </div>
              )}
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
