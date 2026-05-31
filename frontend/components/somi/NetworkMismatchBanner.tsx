'use client';

import { useRef, useEffect } from 'react';
import { useAccount, useChainId, useSwitchChain } from 'wagmi';
import { somniaTestnet } from '@/lib/chains';

export function NetworkMismatchBanner() {
  const { isConnected } = useAccount();
  const chainId = useChainId();
  const { switchChain } = useSwitchChain();
  const btnRef = useRef<HTMLButtonElement>(null);

  const show = isConnected && chainId !== somniaTestnet.id;

  useEffect(() => {
    if (show) btnRef.current?.focus();
  }, [show]);

  if (!show) return null;

  return (
    <div
      role="alert"
      className="w-full bg-accent-warning/10 border-b border-accent-warning/30 py-2 px-4"
    >
      <div className="max-w-7xl mx-auto flex items-center justify-center gap-3 text-sm">
        <span className="text-foreground">
          You&apos;re on the wrong network. Switch to Somnia Testnet to continue.
        </span>
        <button
          ref={btnRef}
          onClick={() => switchChain({ chainId: somniaTestnet.id })}
          className="shrink-0 rounded border border-accent-warning text-accent-warning px-3 py-1 text-xs font-medium hover:bg-accent-warning/10 transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2"
        >
          Switch network
        </button>
      </div>
    </div>
  );
}
