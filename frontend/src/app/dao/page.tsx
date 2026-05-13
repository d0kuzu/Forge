'use client';

import { useState, useEffect } from 'react';
import { useAccount, useReadContract, useWriteContract, useWaitForTransactionReceipt, usePublicClient } from 'wagmi';
import { CONTRACTS } from '@/config/contracts';
import { parseEther, formatEther, encodeFunctionData, keccak256, toHex, parseAbiItem } from 'viem';
import { motion, AnimatePresence } from 'framer-motion';
import { Handshake, Landmark, Play, Vote, Plus, RefreshCw, Layers, CheckCircle2, AlertTriangle } from 'lucide-react';

interface Proposal {
  id: string;
  proposer: string;
  targets: string[];
  values: bigint[];
  calldatas: string[];
  description: string;
  state: number;
  forVotes: bigint;
  againstVotes: bigint;
  abstainVotes: bigint;
  voteEnd: bigint;
}

const STATE_COLORS = [
  'bg-zinc-500/20 text-zinc-400 border-zinc-500/30', // Pending
  'bg-indigo-500/20 text-indigo-300 border-indigo-500/30', // Active
  'bg-red-500/20 text-red-300 border-red-500/30', // Canceled
  'bg-red-500/20 text-red-400 border-red-500/30', // Defeated
  'bg-emerald-500/20 text-emerald-300 border-emerald-500/30', // Succeeded
  'bg-amber-500/20 text-amber-300 border-amber-500/30', // Queued
  'bg-zinc-500/20 text-zinc-400 border-zinc-500/30', // Expired
  'bg-purple-500/20 text-purple-300 border-purple-500/30' // Executed
];

const STATE_NAMES = [
  'Pending',
  'Active',
  'Canceled',
  'Defeated',
  'Succeeded',
  'Queued',
  'Expired',
  'Executed'
];

export default function DAOPage() {
  const { address, isConnected } = useAccount();
  const publicClient = usePublicClient();
  
  const [mounted, setMounted] = useState(false);
  const [proposals, setProposals] = useState<Proposal[]>([]);
  const [isLoadingLogs, setIsLoadingLogs] = useState(false);
  const [activeTab, setActiveTab] = useState<'list' | 'create'>('list');
  const [blockNumber, setBlockNumber] = useState<bigint>(0n);

  // Form State
  const [proposalType, setProposalType] = useState<'gacha' | 'mint'>('gacha');
  const [gachaCost, setGachaCost] = useState('5');
  const [mintAmount, setMintAmount] = useState('1000');
  const [mintReceiver, setMintReceiver] = useState(address || '');
  const [description, setDescription] = useState('Forge Proposal: Change Lootbox Cost to 5 FGC');
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [errorMsg, setErrorMsg] = useState<string | null>(null);
  const [successMsg, setSuccessMsg] = useState<string | null>(null);

  useEffect(() => {
    setMounted(true);
    if (address) {
      setMintReceiver(address);
    }
  }, [address]);

  // Read Proposal Threshold
  const { data: proposalThreshold } = useReadContract({
    ...CONTRACTS.ForgeGovernor,
    functionName: 'proposalThreshold',
  });

  // Read User Delegates
  const { data: userDelegates, refetch: refetchDelegates } = useReadContract({
    ...CONTRACTS.ForgeCoin,
    functionName: 'delegates',
    args: address ? [address] : undefined,
    query: { enabled: !!address },
  });

  // Read User Votes
  const { data: userVotes, refetch: refetchVotes } = useReadContract({
    ...CONTRACTS.ForgeCoin,
    functionName: 'getVotes',
    args: address ? [address] : undefined,
    query: { enabled: !!address },
  });

  // Write Transactions
  const { writeContractAsync } = useWriteContract();

  // Load block number and proposals
  const refreshBlockchainData = async (showLoading = false) => {
    if (!publicClient) return;
    if (showLoading) setIsLoadingLogs(true);
    try {
      // Get current block
      const currentBlock = await publicClient.getBlockNumber();
      setBlockNumber(currentBlock);

      // Refetch user data as well
      refetchDelegates();
      refetchVotes();

      // Fetch all ProposalCreated events
      const logs = await publicClient.getLogs({
        address: CONTRACTS.ForgeGovernor.address,
        event: parseAbiItem(
          'event ProposalCreated(uint256 proposalId, address proposer, address[] targets, uint256[] values, string[] signatures, bytes[] calldatas, uint256 voteStart, uint256 voteEnd, string description)'
        ),
        fromBlock: 41640000n,
      });

      const parsedProposals: Proposal[] = [];

      for (const log of logs) {
        const args = (log as any).args;
        if (!args) continue;

        const propId = args.proposalId;

        // Fetch state and votes dynamically
        const stateValue = await publicClient.readContract({
          ...CONTRACTS.ForgeGovernor,
          functionName: 'state',
          args: [propId],
        }) as number;

        const votesValue = await publicClient.readContract({
          ...CONTRACTS.ForgeGovernor,
          functionName: 'proposalVotes',
          args: [propId],
        }) as [bigint, bigint, bigint];

        parsedProposals.push({
          id: propId.toString(),
          proposer: args.proposer,
          targets: args.targets,
          values: args.values,
          calldatas: args.calldatas,
          description: args.description,
          state: stateValue,
          forVotes: votesValue[1],
          againstVotes: votesValue[0],
          abstainVotes: votesValue[2],
          voteEnd: BigInt(args.voteEnd || 0n),
        });
      }

      setProposals(parsedProposals.reverse());
    } catch (err) {
      console.error('Error fetching proposals logs:', err);
    } finally {
      if (showLoading) setIsLoadingLogs(false);
    }
  };

  useEffect(() => {
    if (!mounted || !publicClient) return;

    // Initial load with spinner
    refreshBlockchainData(true);

    // Live background polling every 4 seconds (no loader flicker)
    const interval = setInterval(() => {
      refreshBlockchainData(false);
    }, 4000);

    return () => clearInterval(interval);
  }, [mounted, publicClient, address]);

  // Self-Delegation (Activate Voting Power)
  const handleDelegate = async () => {
    if (!address) return;
    try {
      const tx = await writeContractAsync({
        ...CONTRACTS.ForgeCoin,
        functionName: 'delegate',
        args: [address],
      });
      if (publicClient) {
        await publicClient.waitForTransactionReceipt({ hash: tx });
      }
      refetchDelegates();
      refetchVotes();
      refreshBlockchainData();
    } catch (err) {
      console.error('Delegation failed:', err);
    }
  };


  // Create Proposal
  const handleCreateProposal = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!address || !description) return;
    setIsSubmitting(true);
    setErrorMsg(null);
    setSuccessMsg(null);

    try {
      let targets: string[] = [];
      let values: bigint[] = [];
      let calldatas: string[] = [];

      if (proposalType === 'gacha') {
        const costWei = parseEther(gachaCost);
        targets = [CONTRACTS.GachaLootbox.address];
        values = [0n];
        calldatas = [
          encodeFunctionData({
            abi: CONTRACTS.GachaLootbox.abi,
            functionName: 'setPrice',
            args: [1n, costWei],
          }),
        ];
      } else {
        const amountWei = parseEther(mintAmount);
        targets = [CONTRACTS.ForgeCoin.address];
        values = [0n];
        calldatas = [
          encodeFunctionData({
            abi: CONTRACTS.ForgeCoin.abi,
            functionName: 'mint',
            args: [mintReceiver as `0x${string}`, amountWei],
          }),
        ];
      }

      const tx = await writeContractAsync({
        ...CONTRACTS.ForgeGovernor,
        functionName: 'propose',
        args: [targets, values, calldatas, description],
      });

      if (publicClient) {
        await publicClient.waitForTransactionReceipt({ hash: tx });
      }
      setSuccessMsg('Proposal submitted successfully!');
      setActiveTab('list');
      refreshBlockchainData();
    } catch (err: any) {
      console.error('Proposal creation failed:', err);
      const message = err.shortMessage || err.message || 'Transaction failed. Check console for details.';
      setErrorMsg(message);
    } finally {
      setIsSubmitting(false);
    }
  };

  // Cast Vote
  const handleVote = async (proposalId: string, support: number) => {
    try {
      const tx = await writeContractAsync({
        ...CONTRACTS.ForgeGovernor,
        functionName: 'castVote',
        args: [BigInt(proposalId), support],
      });
      if (publicClient) {
        await publicClient.waitForTransactionReceipt({ hash: tx });
      }
      refreshBlockchainData();
    } catch (err) {
      console.error('Voting failed:', err);
    }
  };

  // Queue Proposal in Timelock
  const handleQueue = async (prop: Proposal) => {
    try {
      const descriptionHash = keccak256(toHex(prop.description));
      const tx = await writeContractAsync({
        ...CONTRACTS.ForgeGovernor,
        functionName: 'queue',
        args: [prop.targets, prop.values, prop.calldatas, descriptionHash],
      });
      if (publicClient) {
        await publicClient.waitForTransactionReceipt({ hash: tx });
      }
      refreshBlockchainData();
    } catch (err) {
      console.error('Queuing failed:', err);
    }
  };

  // Execute Proposal from Timelock
  const handleExecute = async (prop: Proposal) => {
    try {
      const descriptionHash = keccak256(toHex(prop.description));
      const tx = await writeContractAsync({
        ...CONTRACTS.ForgeGovernor,
        functionName: 'execute',
        args: [prop.targets, prop.values, prop.calldatas, descriptionHash],
      });
      if (publicClient) {
        await publicClient.waitForTransactionReceipt({ hash: tx });
      }
      refreshBlockchainData();
    } catch (err) {
      console.error('Execution failed:', err);
    }
  };

  if (!mounted) return null;

  const isDelegatedSelf = !!(userDelegates && address && (userDelegates as string).toLowerCase() === address.toLowerCase());

  return (
    <div className="flex flex-col items-center gap-8 w-full max-w-5xl mx-auto py-12 px-4">
      {/* Title & Network Status */}
      <div className="text-center flex flex-col gap-2 w-full">
        <div className="flex items-center justify-center gap-2 text-indigo-400 font-bold tracking-wider text-sm uppercase">
          <Handshake className="w-5 h-5" />
          <span>Governance Dashboard</span>
        </div>
        <h1 className="text-4xl font-extrabold tracking-tight bg-clip-text text-transparent bg-gradient-to-r from-zinc-100 to-zinc-400">
          Decentralized Forge DAO
        </h1>
        <p className="text-zinc-400">Vote on parameters, change settings and govern the ecosystem on-chain.</p>
        
        {/* Network Status Badge */}
        <div className="flex items-center justify-center gap-3 mt-3 text-xs font-semibold text-zinc-500">
          <span className="flex items-center gap-1.5 px-3 py-1 bg-zinc-900 border border-zinc-800 rounded-full shadow-inner">
            <span className="w-2 h-2 rounded-full bg-emerald-500 animate-pulse"></span>
            <span>Network: Live L2 Testnet</span>
          </span>
          <span className="flex items-center gap-1.5 px-3 py-1 bg-zinc-900 border border-zinc-800 rounded-full font-mono shadow-inner">
            <span>Block: {blockNumber.toString()}</span>
          </span>
        </div>
      </div>

      {/* User Voting Power Card */}
      {isConnected && (
        <div className="w-full grid grid-cols-1 md:grid-cols-3 gap-6">
          {/* Delegates State */}
          <div className="bg-zinc-900 border border-zinc-800 p-6 rounded-2xl flex flex-col justify-between">
            <div>
              <span className="text-xs text-zinc-500 uppercase tracking-wider block mb-1">Delegated To</span>
              <span className="font-mono text-sm text-zinc-300 break-all font-semibold">
                {(userDelegates as string) && (userDelegates as string) !== '0x0000000000000000000000000000000000000000'
                  ? (userDelegates as string)
                  : 'Nobody'}
              </span>
            </div>
            {!isDelegatedSelf && (
              <button
                onClick={handleDelegate}
                className="mt-4 w-full py-2 bg-red-500/10 hover:bg-red-500/20 border border-red-500/20 hover:border-red-500/40 text-red-300 text-xs font-bold rounded-lg transition-colors flex items-center justify-center gap-2"
              >
                <AlertTriangle className="w-3.5 h-3.5" />
                Activate Voting Power (Self-Delegate)
              </button>
            )}
            {isDelegatedSelf && (
              <div className="mt-4 text-emerald-400 text-xs font-bold flex items-center gap-1.5 justify-center py-2 bg-emerald-500/5 rounded-lg border border-emerald-500/10">
                <CheckCircle2 className="w-4 h-4" />
                Voting Power Active
              </div>
            )}
          </div>

          {/* Voting Weight */}
          <div className="bg-zinc-900 border border-zinc-800 p-6 rounded-2xl flex flex-col justify-between">
            <div>
              <span className="text-xs text-zinc-500 uppercase tracking-wider block mb-1">Voting Weight</span>
              <span className="text-3xl font-extrabold text-white">
                {userVotes !== undefined ? parseFloat(formatEther(userVotes as bigint)).toFixed(2) : '0.00'}{' '}
                <span className="text-sm font-normal text-zinc-400">FGC</span>
              </span>
            </div>
            <p className="text-xs text-zinc-500 mt-2">
              Based on FGC holdings delegated to your address.
            </p>
          </div>

          {/* Quorum and Proposal Threshold */}
          <div className="bg-zinc-900 border border-zinc-800 p-6 rounded-2xl flex flex-col justify-between">
            <div>
              <span className="text-xs text-zinc-500 uppercase tracking-wider block mb-1">Proposal Threshold</span>
              <span className="text-2xl font-bold text-indigo-400">
                {proposalThreshold ? parseFloat(formatEther(proposalThreshold as bigint)).toFixed(0) : '0'}{' '}
                <span className="text-sm font-normal text-zinc-400">FGC</span>
              </span>
            </div>
            <div className="text-xs text-zinc-500 mt-2 flex justify-between">
              <span>Required Quorum: 4%</span>
              <span>Delay: 0 Blocks</span>
            </div>
          </div>
        </div>
      )}

      {/* Main Tabs */}
      <div className="w-full flex border-b border-zinc-800 gap-4 mt-4">
        <button
          onClick={() => setActiveTab('list')}
          className={`pb-4 px-2 font-bold transition-all relative ${
            activeTab === 'list' ? 'text-indigo-400 border-b-2 border-indigo-400' : 'text-zinc-500 hover:text-zinc-300'
          }`}
        >
          Active Proposals ({proposals.length})
        </button>
        <button
          onClick={() => setActiveTab('create')}
          className={`pb-4 px-2 font-bold transition-all relative ${
            activeTab === 'create' ? 'text-indigo-400 border-b-2 border-indigo-400' : 'text-zinc-500 hover:text-zinc-300'
          }`}
        >
          Create Proposal
        </button>
        <button
          onClick={() => refreshBlockchainData(true)}
          disabled={isLoadingLogs}
          className="ml-auto pb-4 px-2 text-zinc-500 hover:text-zinc-300 flex items-center gap-1.5 text-sm"
        >
          <RefreshCw className={`w-4 h-4 ${isLoadingLogs ? 'animate-spin' : ''}`} />
          <span>Refresh</span>
        </button>
      </div>

      {/* Tabs Content */}
      <div className="w-full">
        {activeTab === 'list' && (
          <div className="flex flex-col gap-6 w-full">
            {proposals.length === 0 ? (
              <div className="bg-zinc-900 border border-zinc-800 rounded-3xl p-12 text-center text-zinc-500">
                <Landmark className="w-12 h-12 mx-auto mb-4 text-zinc-700" />
                <p className="font-bold text-lg mb-1">No Proposals Found</p>
                <p className="text-sm text-zinc-600 max-w-sm mx-auto">
                  Create a new on-chain proposal to govern lootbox costs or FGC token parameters!
                </p>
              </div>
            ) : (
              <AnimatePresence>
                {proposals.map((prop) => {
                  const totalVotes = prop.forVotes + prop.againstVotes + prop.abstainVotes;
                  const forPercent = totalVotes > 0n ? Number((prop.forVotes * 100n) / totalVotes) : 0;
                  const againstPercent = totalVotes > 0n ? Number((prop.againstVotes * 100n) / totalVotes) : 0;
                  const stateName = STATE_NAMES[prop.state];

                  return (
                    <motion.div
                      key={prop.id}
                      initial={{ opacity: 0, y: 15 }}
                      animate={{ opacity: 1, y: 0 }}
                      exit={{ opacity: 0, y: -15 }}
                      className="bg-zinc-900 border border-zinc-800 rounded-2xl p-6 shadow-xl relative overflow-hidden"
                    >
                      {/* State Badge */}
                      <div className="flex justify-between items-start mb-4">
                        <div>
                          <span className="text-zinc-500 text-xs font-mono block mb-1">ID: {prop.id.slice(0, 20)}...</span>
                          <h3 className="text-xl font-bold text-white">{prop.description}</h3>
                        </div>
                        <div className="flex flex-col items-end gap-1.5">
                          <span
                            className={`px-3 py-1 text-xs font-bold rounded-full border uppercase tracking-wider ${
                              STATE_COLORS[prop.state]
                            }`}
                          >
                            {stateName}
                          </span>
                          {prop.state === 1 && blockNumber && prop.voteEnd && (
                            <span className="text-zinc-500 text-xs font-medium flex items-center gap-1">
                              <span className="inline-block w-1.5 h-1.5 rounded-full bg-indigo-500 animate-pulse"></span>
                              {BigInt(prop.voteEnd) - BigInt(blockNumber) > 0n ? (
                                `Ends in ${(BigInt(prop.voteEnd) - BigInt(blockNumber)).toString()} blks (~${Math.max(0, Math.floor(Number(BigInt(prop.voteEnd) - BigInt(blockNumber)) * 2))}s)`
                              ) : (
                                "Ending soon..."
                              )}
                            </span>
                          )}
                        </div>
                      </div>

                      {/* Vote Progress Bars */}
                      <div className="my-6 space-y-3">
                        <div className="flex justify-between text-sm font-medium text-zinc-400">
                          <span className="flex items-center gap-1.5">
                            <span className="w-2 h-2 rounded-full bg-emerald-500"></span>
                            For: {parseFloat(formatEther(prop.forVotes)).toFixed(0)} FGC ({forPercent}%)
                          </span>
                          <span className="flex items-center gap-1.5">
                            Against: {parseFloat(formatEther(prop.againstVotes)).toFixed(0)} FGC ({againstPercent}%)
                            <span className="w-2 h-2 rounded-full bg-red-500"></span>
                          </span>
                        </div>
                        <div className="w-full h-3 bg-zinc-950 rounded-full overflow-hidden flex">
                          <div
                            style={{ width: `${forPercent}%` }}
                            className="h-full bg-gradient-to-r from-emerald-500 to-teal-400 transition-all duration-500"
                          ></div>
                          <div
                            style={{ width: `${againstPercent}%` }}
                            className="h-full bg-gradient-to-r from-red-500 to-rose-400 transition-all duration-500"
                          ></div>
                        </div>
                      </div>

                      {/* Action buttons */}
                      <div className="flex flex-wrap gap-3 border-t border-zinc-800/50 pt-4 items-center justify-between">
                        <span className="text-xs text-zinc-500">
                          Proposed by:{' '}
                          <span className="font-mono text-zinc-400">
                            {prop.proposer.slice(0, 6)}...{prop.proposer.slice(-4)}
                          </span>
                        </span>

                        <div className="flex gap-2">
                          {/* Voting Phase Actions */}
                          {prop.state === 1 && (
                            <>
                              <button
                                onClick={() => handleVote(prop.id, 1)}
                                className="px-4 py-2 bg-emerald-500/10 hover:bg-emerald-500 text-emerald-400 hover:text-white border border-emerald-500/20 rounded-xl font-bold transition-all text-sm active:scale-95"
                              >
                                👍 Vote For
                              </button>
                              <button
                                onClick={() => handleVote(prop.id, 0)}
                                className="px-4 py-2 bg-red-500/10 hover:bg-red-500 text-red-400 hover:text-white border border-red-500/20 rounded-xl font-bold transition-all text-sm active:scale-95"
                              >
                                👎 Vote Against
                              </button>
                              <button
                                onClick={() => handleVote(prop.id, 2)}
                                className="px-4 py-2 bg-zinc-800 hover:bg-zinc-700 text-zinc-300 rounded-xl font-bold transition-all text-sm active:scale-95"
                              >
                                Abstain
                              </button>
                            </>
                          )}

                          {/* Succeeded Actions -> Queue */}
                          {prop.state === 4 && (
                            <button
                              onClick={() => handleQueue(prop)}
                              className="px-6 py-2.5 bg-amber-600 hover:bg-amber-500 text-white rounded-xl font-bold transition-all text-sm shadow-lg shadow-amber-600/20 active:scale-95 flex items-center gap-1.5"
                            >
                              <Layers className="w-4 h-4" />
                              <span>Queue in Timelock</span>
                            </button>
                          )}

                          {/* Queued Actions -> Execute */}
                          {prop.state === 5 && (
                            <button
                              onClick={() => handleExecute(prop)}
                              className="px-6 py-2.5 bg-emerald-600 hover:bg-emerald-500 text-white rounded-xl font-bold transition-all text-sm shadow-lg shadow-emerald-600/20 active:scale-95 flex items-center gap-1.5"
                            >
                              <CheckCircle2 className="w-4 h-4" />
                              <span>Execute Proposal ✅</span>
                            </button>
                          )}

                          {/* Executed State Badge */}
                          {prop.state === 7 && (
                            <div className="px-4 py-2 bg-purple-500/10 border border-purple-500/20 text-purple-300 text-xs font-bold rounded-xl flex items-center gap-1.5">
                              <CheckCircle2 className="w-4 h-4" />
                              Executed & Applied
                            </div>
                          )}
                        </div>
                      </div>
                    </motion.div>
                  );
                })}
              </AnimatePresence>
            )}
          </div>
        )}

        {activeTab === 'create' && (
          <div className="w-full max-w-2xl mx-auto bg-zinc-900 border border-zinc-800 rounded-3xl p-8 shadow-2xl relative overflow-hidden">
            <h2 className="text-2xl font-bold text-white mb-6 flex items-center gap-2">
              <Plus className="w-6 h-6 text-indigo-400" />
              <span>Draft Governance Proposal</span>
            </h2>

            {/* Wallet Not Connected */}
            {!isConnected && (
              <div className="bg-red-500/10 border border-red-500/20 text-red-300 p-6 rounded-2xl flex flex-col gap-3 mb-6">
                <div className="flex items-center gap-2 font-bold text-sm">
                  <AlertTriangle className="w-5 h-5 text-red-400 animate-pulse" />
                  <span>Wallet Not Connected</span>
                </div>
                <p className="text-xs text-zinc-400">
                  Please connect your Web3 wallet to draft and submit proposals to the DAO.
                </p>
              </div>
            )}

            {/* Voting Power Not Activated */}
            {isConnected && !isDelegatedSelf && (
              <div className="bg-amber-500/10 border border-amber-500/20 text-amber-300 p-6 rounded-2xl flex flex-col gap-3 mb-6">
                <div className="flex items-center gap-2 font-bold text-sm">
                  <AlertTriangle className="w-5 h-5 text-amber-400" />
                  <span>Voting Power Not Activated</span>
                </div>
                <p className="text-xs text-zinc-400">
                  You must self-delegate your voting power to activate your FGC voting weight before you can submit proposals.
                </p>
                <button
                  type="button"
                  onClick={handleDelegate}
                  className="w-full py-2 bg-amber-500 hover:bg-amber-600 text-zinc-950 text-xs font-bold rounded-lg transition-all"
                >
                  Activate Voting Power (Self-Delegate)
                </button>
              </div>
            )}

            {/* Insufficient Voting Power */}
            {isConnected && isDelegatedSelf && userVotes !== undefined && proposalThreshold !== undefined && (userVotes as bigint) < (proposalThreshold as bigint) && (
              <div className="bg-red-500/10 border border-red-500/20 text-red-300 p-6 rounded-2xl flex flex-col gap-3 mb-6">
                <div className="flex items-center gap-2 font-bold text-sm">
                  <AlertTriangle className="w-5 h-5 text-red-400" />
                  <span>Insufficient Voting Weight</span>
                </div>
                <p className="text-xs text-zinc-400">
                  You need at least <span className="font-bold text-white">{parseFloat(formatEther(proposalThreshold as bigint)).toFixed(0)} FGC</span> of voting power to submit a proposal. Your current weight is <span className="font-bold text-white">{parseFloat(formatEther(userVotes as bigint)).toFixed(2)} FGC</span>.
                </p>
                <p className="text-xs text-zinc-400">
                  Staking FGC in the vaults, participating in liquidity pools, or obtaining more FGC tokens can increase your balance.
                </p>
              </div>
            )}

            {/* Error Message */}
            {errorMsg && (
              <div className="bg-red-500/15 border border-red-500/20 text-red-400 p-4 rounded-xl text-xs font-medium mb-6">
                {errorMsg}
              </div>
            )}

            {/* Success Message */}
            {successMsg && (
              <div className="bg-emerald-500/15 border border-emerald-500/20 text-emerald-400 p-4 rounded-xl text-xs font-medium mb-6">
                {successMsg}
              </div>
            )}

            <form onSubmit={handleCreateProposal} className="space-y-6">
              {/* Type Select */}
              <div>
                <label className="block text-sm font-medium text-zinc-400 mb-2">Proposal Type</label>
                <div className="grid grid-cols-2 gap-4">
                  <button
                    type="button"
                    onClick={() => {
                      setProposalType('gacha');
                      setDescription('Forge Proposal: Change Lootbox Cost to 5 FGC');
                    }}
                    className={`py-4 px-4 rounded-xl border text-center font-bold transition-all flex flex-col items-center justify-center gap-2 ${
                      proposalType === 'gacha'
                        ? 'bg-indigo-600/10 border-indigo-500 text-indigo-400'
                        : 'bg-zinc-950/50 border-zinc-800 text-zinc-400 hover:bg-zinc-800/30'
                    }`}
                  >
                    <Vote className="w-6 h-6" />
                    <span>Change Gacha Price</span>
                  </button>
                  <button
                    type="button"
                    onClick={() => {
                      setProposalType('mint');
                      setDescription(`Forge Proposal: Mint 1000 FGC to Admin`);
                    }}
                    className={`py-4 px-4 rounded-xl border text-center font-bold transition-all flex flex-col items-center justify-center gap-2 ${
                      proposalType === 'mint'
                        ? 'bg-indigo-600/10 border-indigo-500 text-indigo-400'
                        : 'bg-zinc-950/50 border-zinc-800 text-zinc-400 hover:bg-zinc-800/30'
                    }`}
                  >
                    <Plus className="w-6 h-6" />
                    <span>Mint FGC Tokens</span>
                  </button>
                </div>
              </div>

              {/* Dynamic Inputs */}
              {proposalType === 'gacha' && (
                <div>
                  <label className="block text-sm font-medium text-zinc-400 mb-2">New Gacha Cost (FGC)</label>
                  <input
                    type="number"
                    value={gachaCost}
                    onChange={(e) => {
                      setGachaCost(e.target.value);
                      setDescription(`Forge Proposal: Change Lootbox Cost to ${e.target.value} FGC`);
                    }}
                    className="w-full px-4 py-3 bg-zinc-950 border border-zinc-800 rounded-xl text-white font-semibold focus:border-indigo-500 focus:outline-none"
                    placeholder="Enter cost (e.g. 5)"
                    min="1"
                    required
                  />
                </div>
              )}

              {proposalType === 'mint' && (
                <div className="grid grid-cols-1 gap-4">
                  <div>
                    <label className="block text-sm font-medium text-zinc-400 mb-2">Amount of FGC to Mint</label>
                    <input
                      type="number"
                      value={mintAmount}
                      onChange={(e) => {
                        setMintAmount(e.target.value);
                        setDescription(`Forge Proposal: Mint ${e.target.value} FGC to Admin`);
                      }}
                      className="w-full px-4 py-3 bg-zinc-950 border border-zinc-800 rounded-xl text-white font-semibold focus:border-indigo-500 focus:outline-none"
                      placeholder="Enter amount (e.g. 1000)"
                      min="1"
                      required
                    />
                  </div>
                  <div>
                    <label className="block text-sm font-medium text-zinc-400 mb-2">Receiver Address</label>
                    <input
                      type="text"
                      value={mintReceiver}
                      onChange={(e) => setMintReceiver(e.target.value)}
                      className="w-full px-4 py-3 bg-zinc-950 border border-zinc-800 rounded-xl text-white font-mono text-sm focus:border-indigo-500 focus:outline-none"
                      placeholder="0x..."
                      required
                    />
                  </div>
                </div>
              )}

              {/* Description Display */}
              <div>
                <label className="block text-sm font-medium text-zinc-400 mb-2">Proposal Description</label>
                <textarea
                  value={description}
                  onChange={(e) => setDescription(e.target.value)}
                  className="w-full px-4 py-3 bg-zinc-950 border border-zinc-800 rounded-xl text-white focus:border-indigo-500 focus:outline-none h-24"
                  placeholder="Describe your proposal..."
                  required
                />
              </div>

              {/* Submit Button */}
              <button
                type="submit"
                disabled={
                  isSubmitting ||
                  !isConnected ||
                  !isDelegatedSelf ||
                  (userVotes !== undefined && proposalThreshold !== undefined && (userVotes as bigint) < (proposalThreshold as bigint))
                }
                className="w-full py-4 bg-indigo-600 hover:bg-indigo-500 disabled:bg-zinc-800 disabled:text-zinc-600 disabled:border-zinc-800/50 disabled:shadow-none text-white border border-transparent rounded-xl font-bold transition-all shadow-lg shadow-indigo-600/20 active:scale-95 flex items-center justify-center gap-2"
              >
                {isSubmitting ? (
                  <>
                    <RefreshCw className="w-5 h-5 animate-spin" />
                    <span>Submitting Proposal to Blockchain...</span>
                  </>
                ) : !isConnected ? (
                  <span>Locked: Connect Wallet</span>
                ) : !isDelegatedSelf ? (
                  <span>Locked: Activate Voting Power</span>
                ) : userVotes !== undefined && proposalThreshold !== undefined && (userVotes as bigint) < (proposalThreshold as bigint) ? (
                  <span>Locked: Insufficient Voting Weight</span>
                ) : (
                  <span>Submit Proposal to Blockchain</span>
                )}
              </button>
            </form>
          </div>
        )}
      </div>
    </div>
  );
}
