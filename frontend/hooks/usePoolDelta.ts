'use client';

import { useState, useEffect, useCallback } from 'react';

interface PoolDelta {
  yesPool: bigint;
  noPool: bigint;
}

const ZERO_DELTA: PoolDelta = { yesPool: 0n, noPool: 0n };

export function usePoolDelta(marketId: bigint) {
  const [delta, setDelta] = useState<PoolDelta>(ZERO_DELTA);

  useEffect(() => {
    setDelta(ZERO_DELTA);
  }, [marketId]);

  const addOptimistic = useCallback((side: 0 | 1, amount: bigint) => {
    setDelta(prev =>
      side === 0
        ? { ...prev, yesPool: prev.yesPool + amount }
        : { ...prev, noPool: prev.noPool + amount }
    );
  }, []);

  const rollback = useCallback(() => setDelta(ZERO_DELTA), []);
  const clear = useCallback(() => setDelta(ZERO_DELTA), []);

  return { delta, addOptimistic, rollback, clear };
}
