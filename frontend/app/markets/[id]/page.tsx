import type { Metadata } from 'next';
import MarketDetailClient from './MarketDetailClient';

export async function generateMetadata(
  { params }: { params: Promise<{ id: string }> }
): Promise<Metadata> {
  const { id } = await params;
  return {
    title: `Market #${id}`,
    description: `Autonomous AI-resolved prediction market #${id} on Somnia`,
    openGraph: {
      title: `Market #${id} — Somi`,
      description: `Autonomous AI-resolved prediction market #${id} on Somnia`,
      images: [
        {
          url: '/og-image.png',
          width: 1200,
          height: 630,
          alt: `Somi market #${id} — autonomous AI-resolved prediction market`,
        },
      ],
    },
    twitter: {
      card: 'summary_large_image',
      title: `Market #${id} — Somi`,
      description: `Autonomous AI-resolved prediction market #${id} on Somnia`,
      images: ['/og-image.png'],
    },
  };
}

export default async function MarketDetailPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  return <MarketDetailClient id={id} />;
}
