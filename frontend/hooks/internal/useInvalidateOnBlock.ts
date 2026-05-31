'use client';

import { useEffect } from 'react';
import { useBlockNumber } from 'wagmi';
import { useQueryClient } from '@tanstack/react-query';

export function useInvalidateOnBlock(queryKey: readonly unknown[] | undefined) {
  const queryClient = useQueryClient();
  const { data: blockNumber } = useBlockNumber({ watch: true });

  useEffect(() => {
    if (!queryKey || blockNumber === undefined) return;
    queryClient.invalidateQueries({ queryKey });
  }, [blockNumber, queryClient, queryKey]);
}
