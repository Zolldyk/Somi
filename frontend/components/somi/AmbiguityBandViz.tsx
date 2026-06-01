import { cn } from '@/lib/utils';

const BPS_DENOM = 10_000n;

export interface AmbiguityBandVizProps {
  threshold: bigint;
  bandBps: bigint;
  currentValue?: bigint;
  variant?: 'sm' | 'md';
  className?: string;
}

export function AmbiguityBandViz({
  threshold,
  bandBps,
  currentValue,
  variant = 'sm',
  className,
}: AmbiguityBandVizProps) {
  const clampedBandBps = bandBps > BPS_DENOM ? BPS_DENOM : bandBps;

  if (threshold === 0n || clampedBandBps === 0n) {
    return (
      <div
        role="img"
        aria-label="Ambiguity band: no threshold defined"
        className={cn('w-full rounded-sm bg-muted', className)}
        style={{ height: variant === 'md' ? 24 : 12 }}
      />
    );
  }

  const bandHalf = (threshold * clampedBandBps) / BPS_DENOM;
  const bandLow = threshold - bandHalf;
  const bandHigh = threshold + bandHalf;

  const displayRange = bandHalf * 6n;
  const displayMin = threshold - displayRange / 2n;
  const displayMax = threshold + displayRange / 2n;

  const toPos = (v: bigint): number =>
    Number(((v - displayMin) * 100n) / (displayMax - displayMin));

  const bandLowPct = toPos(bandLow);
  const bandHighPct = toPos(bandHigh);
  const thresholdPct = toPos(threshold);

  let markerClass: string | undefined;
  let markerPos: number | undefined;
  if (currentValue !== undefined) {
    markerPos = Math.max(0, Math.min(100, toPos(currentValue)));
    const isInBand = currentValue >= bandLow && currentValue <= bandHigh;
    const isAbove = currentValue > bandHigh;
    markerClass = isInBand ? 'bg-accent-llm' : isAbove ? 'bg-accent-yes' : 'bg-accent-no';
  }

  const bandPctLabel = (Number(clampedBandBps) / 100).toFixed(2).replace(/\.?0+$/, '');

  const ariaLabel = [
    `Ambiguity band: threshold ${Number(threshold).toLocaleString()}, ±${bandPctLabel}%`,
    currentValue !== undefined ? `, fetched value ${Number(currentValue).toLocaleString()}` : '',
  ].join('');

  return (
    <div className={cn('w-full', className)}>
      <div
        role="img"
        aria-label={ariaLabel}
        className="relative w-full rounded-sm bg-muted"
        style={{ height: variant === 'md' ? 24 : 12 }}
      >
        {/* shaded ambiguity band */}
        <div
          className="absolute inset-y-0 bg-accent-llm/20"
          style={{ left: `${bandLowPct}%`, right: `${100 - bandHighPct}%` }}
        />
        {/* threshold midline */}
        <div
          className="absolute inset-y-0 w-px bg-muted-foreground/40"
          style={{ left: `${thresholdPct}%` }}
        />
        {/* current value marker */}
        {currentValue !== undefined && markerPos !== undefined && markerClass !== undefined && (
          <div
            className={cn('absolute inset-y-0 w-0.5', markerClass)}
            style={{ left: `${markerPos}%` }}
          />
        )}
      </div>

      {variant === 'md' && (
        <div className="mt-0.5 flex justify-between font-mono text-xs text-muted-foreground">
          <span>{Number(bandLow).toLocaleString()}</span>
          <span>{Number(threshold).toLocaleString()}</span>
          <span>{Number(bandHigh).toLocaleString()}</span>
        </div>
      )}
    </div>
  );
}
