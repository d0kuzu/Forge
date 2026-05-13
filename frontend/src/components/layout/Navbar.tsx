'use client';

import * as React from 'react';
import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { ConnectButton } from '@rainbow-me/rainbowkit';
import { Hammer, Coins, Sparkles, Store, Handshake, Landmark, Shield } from 'lucide-react';
import { useAccount, useReadContract } from 'wagmi';
import { CONTRACTS } from '@/config/contracts';
import { formatEther } from 'viem';

const navItems = [
  { name: 'Dashboard', href: '/', icon: Store },
  { name: 'Gacha', href: '/gacha', icon: Sparkles },
  { name: 'DEX', href: '/amm', icon: Coins },
  { name: 'Craft', href: '/craft', icon: Hammer },
  { name: 'Vaults', href: '/vaults', icon: Landmark },
  { name: 'DAO', href: '/dao', icon: Handshake },
];

export function Navbar() {
  const pathname = usePathname();
  const { address, isConnected } = useAccount();
  const [mounted, setMounted] = React.useState(false);

  React.useEffect(() => {
    setMounted(true);
  }, []);

  // Read ForgeCoin Balance
  const { data: coinBalance } = useReadContract({
    ...CONTRACTS.ForgeCoin,
    functionName: 'balanceOf',
    args: address ? [address] : undefined,
    query: {
      enabled: !!address,
      refetchInterval: 3000,
    }
  });

  // Read Dust Balance (Item ID: 0)
  const { data: dustBalance } = useReadContract({
    ...CONTRACTS.ForgeItems,
    functionName: 'balanceOf',
    args: address ? [address, 0n] : undefined,
    query: {
      enabled: !!address,
      refetchInterval: 3000,
    }
  });

  return (
    <nav className="border-b border-zinc-800 bg-zinc-950/50 backdrop-blur-xl sticky top-0 z-50">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div className="flex items-center justify-between h-16">
          <div className="flex items-center">
            <Link href="/" className="flex items-center gap-2 text-xl font-bold bg-clip-text text-transparent bg-gradient-to-r from-indigo-400 to-purple-400">
              <Hammer className="w-6 h-6 text-indigo-400" />
              <span>Decentralized Forge</span>
            </Link>
            <div className="hidden md:block ml-10">
              <div className="flex items-baseline space-x-4">
                {navItems.map((item) => {
                  const isActive = pathname === item.href || (item.href !== '/' && pathname?.startsWith(item.href));
                  return (
                    <Link
                      key={item.name}
                      href={item.href}
                      className={`flex items-center gap-2 px-3 py-2 rounded-md text-sm font-medium transition-all duration-200 ${
                        isActive
                          ? 'bg-indigo-500/10 text-indigo-400'
                          : 'text-zinc-400 hover:bg-zinc-800 hover:text-white'
                      }`}
                    >
                      <item.icon className="w-4 h-4" />
                      {item.name}
                    </Link>
                  );
                })}
              </div>
            </div>
          </div>
          <div className="flex items-center gap-4">
            {mounted && isConnected && (
              <div className="hidden lg:flex items-center gap-4 px-4 py-2 bg-zinc-900 rounded-lg border border-zinc-800">
                <div className="flex items-center gap-2">
                  <div className="w-2 h-2 rounded-full bg-indigo-400 shadow-[0_0_8px_rgba(129,140,248,0.8)]"></div>
                  <span className="text-sm font-medium text-zinc-300">
                    {coinBalance !== undefined ? parseFloat(formatEther(coinBalance as bigint)).toFixed(2) : '0.00'} FGC
                  </span>
                </div>
                <div className="w-px h-4 bg-zinc-800"></div>
                <div className="flex items-center gap-2">
                  <div className="w-2 h-2 rounded-full bg-purple-400 shadow-[0_0_8px_rgba(192,132,252,0.8)]"></div>
                  <span className="text-sm font-medium text-zinc-300">
                    {dustBalance !== undefined ? parseFloat(formatEther(dustBalance as bigint)).toFixed(2) : '0.00'} DUST
                  </span>
                </div>
              </div>
            )}
            <ConnectButton showBalance={false} />
          </div>
        </div>
      </div>
    </nav>
  );
}
