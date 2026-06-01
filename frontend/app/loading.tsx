import { FeaturedMarketCard } from '@/components/somi/FeaturedMarketCard';
import { MarketCard } from '@/components/somi/MarketCard';
import { FEATURED_MARKET_ID } from '@/lib/constants';

const SKELETON_COUNT = 4;

export default function HomeLoading() {
  return (
    <div className="max-w-7xl mx-auto px-4 lg:px-12 py-8 lg:py-12">
      <div className="flex flex-col gap-8 lg:gap-12">
        <section>
          <h1 className="text-3xl lg:text-4xl font-semibold tracking-tight">
            Autonomous prediction markets that resolve themselves on Somnia.
          </h1>
          <p className="mt-3 max-w-2xl text-base text-muted-foreground">
            Bet on a question, walk away, return to a verdict — and read the receipt of how it was decided.
          </p>
        </section>
        {FEATURED_MARKET_ID !== undefined && <FeaturedMarketCard.Skeleton />}
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
          {Array.from({ length: SKELETON_COUNT }).map((_, i) => (
            <MarketCard.Skeleton key={i} />
          ))}
        </div>
      </div>
    </div>
  );
}
