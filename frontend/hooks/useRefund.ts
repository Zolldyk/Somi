'use client';

import { useWriteContract, useWaitForTransactionReceipt } from 'wagmi';
import { toast } from 'sonner';
import { predictionMarketAbi } from '@/lib/abi';
import { CONTRACT_ADDRESS } from '@/lib/constants';
import { translateContractError } from '@/lib/errors';

function isUserRejection(error: unknown): boolean {
  if (typeof error !== 'object' || error === null) return false;
  const msg =
    (error as { shortMessage?: string; message?: string }).shortMessage ??
    (error as { message?: string }).message ??
    '';
  return msg.toLowerCase().includes('rejected') || msg.toLowerCase().includes('denied');
}

export function useRefund(marketId: bigint) {
  const { writeContract, isPending, data: txHash } = useWriteContract();
  const { isLoading: isConfirming, isSuccess: isConfirmed } = useWaitForTransactionReceipt({
    hash: txHash,
  });

  function refund() {
    if (!CONTRACT_ADDRESS) return;
    writeContract(
      {
        address: CONTRACT_ADDRESS,
        abi: predictionMarketAbi,
        functionName: 'refund',
        args: [marketId],
      },
      {
        onError(err) {
          const msg = translateContractError(err);
          if (msg) toast(msg);
          else if (isUserRejection(err)) toast('Refund not submitted.');
          else toast('Refund failed. Please try again.');
        },
      }
    );
  }

  return { refund, isPending, isConfirming, isConfirmed };
}
