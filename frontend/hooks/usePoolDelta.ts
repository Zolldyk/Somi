'use client';

import { useState, useCallback } from 'react';

interface PoolDelta {
  yesPool: bigint;
  noPool: bigint;
}

const ZERO_DELTA: PoolDelta = { yesPool: 0n, noPool: 0n };

export function usePoolDelta(marketId: bigint) {
  const [state, setState] = useState<{ marketId: bigint; delta: PoolDelta }>({
    marketId,
    delta: ZERO_DELTA,
  });

  const delta = state.marketId === marketId ? state.delta : ZERO_DELTA;

  const addOptimistic = useCallback((side: 0 | 1, amount: bigint) => {
    setState((prev) => {
      const prevDelta = prev.marketId === marketId ? prev.delta : ZERO_DELTA;
      return {
        marketId,
        delta:
          side === 0
            ? { ...prevDelta, yesPool: prevDelta.yesPool + amount }
            : { ...prevDelta, noPool: prevDelta.noPool + amount },
      };
    });
  }, [marketId]);

  const rollback = useCallback(() => setState({ marketId, delta: ZERO_DELTA }), [marketId]);
  const clear = useCallback(() => setState({ marketId, delta: ZERO_DELTA }), [marketId]);

  return { delta, addOptimistic, rollback, clear };
}
