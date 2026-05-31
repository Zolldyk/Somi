'use client';

import { useBalance } from 'wagmi';
import { CONTRACT_ADDRESS } from '@/lib/constants';

export function useReactivityBalance() {
  const result = useBalance({
    address: CONTRACT_ADDRESS,
    query: { enabled: !!CONTRACT_ADDRESS },
  });

  return {
    balance: result.data?.value,
    isPending: result.isPending,
    isFetching: result.isFetching,
    isError: result.isError,
    error: result.error,
  };
}
