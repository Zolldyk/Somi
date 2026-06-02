import { Skeleton } from '@/components/ui/skeleton';
import { StatusPill } from '@/components/somi/StatusPill';
import { PoolBar } from '@/components/somi/PoolBar';
import { BetForm } from '@/components/somi/BetForm';

export default function MarketDetailLoading() {
  return (
    <div className="max-w-4xl mx-auto px-4 lg:px-8 py-8 lg:py-12">
      <div className="flex flex-col gap-6">
        <StatusPill.Skeleton />
        <div className="space-y-2">
          <Skeleton className="h-8 w-full" />
          <Skeleton className="h-8 w-3/4" />
        </div>
        <PoolBar.Skeleton variant="lg" />
        <Skeleton className="h-4 w-48" />
        <div className="space-y-1.5">
          <Skeleton className="h-3.5 w-full" />
          <Skeleton className="h-3.5 w-full" />
          <Skeleton className="h-3.5 w-4/5" />
          <Skeleton className="h-3.5 w-3/4" />
        </div>
        <BetForm.Skeleton />
      </div>
    </div>
  );
}
