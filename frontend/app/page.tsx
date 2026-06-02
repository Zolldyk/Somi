import type { Metadata } from 'next';
import { FEATURED_MARKET_ID } from '@/lib/constants';
import { AttentionBanner } from '@/components/somi/AttentionBanner';
import { FeaturedMarketSlot } from '@/components/somi/FeaturedMarketSlot';
import { MarketGrid } from '@/components/somi/MarketGrid';

export const metadata: Metadata = {
  title: 'Markets · Somi',
};

export default function HomePage() {
  return (
    <>
      <AttentionBanner />
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

          {FEATURED_MARKET_ID !== undefined && <FeaturedMarketSlot marketId={FEATURED_MARKET_ID} />}

          <MarketGrid />
        </div>
      </div>
    </>
  );
}
