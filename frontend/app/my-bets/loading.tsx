'use client';

import { Skeleton } from '@/components/ui/skeleton';
import { PoolBar } from '@/components/somi/PoolBar';

function CompactRowSkeleton() {
  return (
    <div className="flex flex-col gap-3 px-3 py-3 rounded-xl bg-card ring-1 ring-foreground/10">
      <Skeleton className="h-4 w-24 rounded-sm" />
      <Skeleton className="h-5 w-full" />
      <PoolBar.Skeleton variant="sm" />
      <Skeleton className="h-3.5 w-2/3" />
    </div>
  );
}

export default function MyBetsLoading() {
  return (
    <div className="max-w-4xl mx-auto px-4 lg:px-8 py-8 lg:py-12">
      <Skeleton className="h-8 w-32 mb-8" />
      <div className="flex flex-col gap-3">
        <CompactRowSkeleton />
        <CompactRowSkeleton />
        <CompactRowSkeleton />
        <CompactRowSkeleton />
      </div>
    </div>
  );
}
