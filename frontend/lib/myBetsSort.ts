import type { Market, UserPosition } from '@/types/market';

export type PositionBucket =
  | 'claimable'
  | 'refundable-invalid'
  | 'refundable-disputed'
  | 'resolving'
  | 'open'
  | 'settled-loss';

export interface GroupedPositions {
  claimable: UserPosition[];
  'refundable-invalid': UserPosition[];
  'refundable-disputed': UserPosition[];
  resolving: UserPosition[];
  open: UserPosition[];
  'settled-loss': UserPosition[];
}

export function classifySinglePosition(
  market: Market,
  yesStake: bigint,
  noStake: bigint,
  claimed: boolean,
  refunded: boolean
): PositionBucket {
  if (market.status === 'Resolved') {
    const isWinner =
      (market.verdict === 'YES' && yesStake > 0n) ||
      (market.verdict === 'NO' && noStake > 0n);
    if (isWinner && !claimed) return 'claimable';
    return 'settled-loss';
  }
  if (market.status === 'Refunded') {
    if (yesStake + noStake > 0n && !refunded) return 'refundable-invalid';
    return 'settled-loss';
  }
  if (market.status === 'Disputed') {
    if (yesStake + noStake > 0n && !refunded) return 'refundable-disputed';
    return 'settled-loss';
  }
  if (market.status === 'Resolving' || market.status === 'LLMResolving') return 'resolving';
  return 'open';
}

export function classifyAndSort(positions: UserPosition[]): GroupedPositions {
  const groups: GroupedPositions = {
    claimable: [],
    'refundable-invalid': [],
    'refundable-disputed': [],
    resolving: [],
    open: [],
    'settled-loss': [],
  };

  for (const pos of positions) {
    const bucket = classifySinglePosition(
      pos.market,
      pos.yesStake,
      pos.noStake,
      pos.claimed,
      pos.refunded
    );
    groups[bucket].push(pos);
  }

  const asc = (a: UserPosition, b: UserPosition) =>
    a.market.resolutionTime < b.market.resolutionTime ? -1 : 1;
  const desc = (a: UserPosition, b: UserPosition) =>
    a.market.resolutionTime > b.market.resolutionTime ? -1 : 1;

  groups.claimable.sort(asc);
  groups['refundable-invalid'].sort(asc);
  groups['refundable-disputed'].sort(asc);
  groups.resolving.sort(asc);
  groups.open.sort(asc);
  groups['settled-loss'].sort(desc);

  return groups;
}
