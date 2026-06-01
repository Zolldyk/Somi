'use client';

import { useEffect, useState } from 'react';

function computeLabel(resolutionTime: bigint): string | null {
  const diffSec = Number(resolutionTime) - Math.floor(Date.now() / 1000);
  if (diffSec < 0) return null;
  if (diffSec === 0) return 'now';
  const totalMin = Math.floor(diffSec / 60);
  const totalHr = Math.floor(totalMin / 60);
  const totalDay = Math.floor(totalHr / 24);
  if (totalDay >= 1) return `${totalDay}d ${totalHr % 24}h`;
  if (totalHr >= 1) return `${totalHr}h ${totalMin % 60}m`;
  if (totalMin >= 1) return `${totalMin}m`;
  return '<1m';
}

export function CountdownTimer({ resolutionTime }: { resolutionTime: bigint }) {
  const [label, setLabel] = useState<string | null>(null);

  useEffect(() => {
    setLabel(computeLabel(resolutionTime));
    const interval = setInterval(() => {
      setLabel(computeLabel(resolutionTime));
    }, 60_000);
    return () => clearInterval(interval);
  }, [resolutionTime]);

  if (label === null) return null;

  return (
    <span
      className="font-mono text-sm tabular-nums"
      aria-live="off"
      aria-label={`Resolves in ${label}`}
    >
      {label}
    </span>
  );
}
