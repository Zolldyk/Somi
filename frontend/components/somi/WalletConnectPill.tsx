'use client';

import { useAccount, useBalance, useChainId, useDisconnect, useSwitchChain } from 'wagmi';
import { useConnectModal } from '@rainbow-me/rainbowkit';
import { formatUnits } from 'viem';
import { ChevronDown } from 'lucide-react';
import { Button } from '@/components/ui/button';
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu';
import { somniaTestnet } from '@/lib/chains';

function truncateAddress(addr: string): string {
  return `${addr.slice(0, 6)}…${addr.slice(-4)}`;
}

export function WalletConnectPill() {
  const { address, isConnected } = useAccount();
  const chainId = useChainId();
  const { disconnect } = useDisconnect();
  const { switchChain } = useSwitchChain();
  const { connectModalOpen, openConnectModal } = useConnectModal();
  const { data: balance } = useBalance({ address, query: { enabled: !!address } });

  const isWrongNetwork = isConnected && chainId !== somniaTestnet.id;

  const formattedBalance = balance
    ? Number(formatUnits(balance.value, 18)).toFixed(2)
    : '0.00';

  if (!isConnected) {
    return (
      <Button
        onClick={connectModalOpen ? undefined : openConnectModal ?? undefined}
        disabled={connectModalOpen}
        aria-busy={connectModalOpen}
        className="focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 focus-visible:ring-offset-background"
      >
        Connect Wallet
      </Button>
    );
  }

  if (isWrongNetwork) {
    return (
      <Button
        variant="outline"
        className="border-accent-no text-accent-no hover:bg-accent-no/10 focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 focus-visible:ring-offset-background"
        onClick={() => switchChain({ chainId: somniaTestnet.id })}
      >
        Switch network
      </Button>
    );
  }

  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button
          variant="outline"
          aria-label={truncateAddress(address!)}
          className="focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 focus-visible:ring-offset-background"
        >
          <span className="font-mono tabular-nums">
            {truncateAddress(address!)} &middot; {formattedBalance} STT
          </span>
          <ChevronDown className="ml-1 h-4 w-4" />
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end">
        <DropdownMenuItem onSelect={() => navigator.clipboard.writeText(address!)}>
          Copy address
        </DropdownMenuItem>
        <DropdownMenuItem
          onSelect={() =>
            window.open(
              `https://shannon-explorer.somnia.network/address/${address}`,
              '_blank'
            )
          }
        >
          View on explorer
        </DropdownMenuItem>
        <DropdownMenuItem onSelect={() => disconnect()}>
          Disconnect
        </DropdownMenuItem>
      </DropdownMenuContent>
    </DropdownMenu>
  );
}
