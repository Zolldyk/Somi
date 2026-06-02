export interface MarketTemplate {
  id: 'coingecko' | 'espn' | 'custom';
  label: string;
  description: string;
  dataSource: string;
  jsonSelector: string;
  recommendedBandBps: number;
  thresholdPlaceholder?: string;
}

export const TEMPLATES: MarketTemplate[] = [
  {
    id: 'coingecko',
    label: 'CoinGecko (crypto price)',
    description:
      'Live crypto price from CoinGecko. Edit the token name in the URL and selector to match your market.',
    dataSource:
      'https://api.coingecko.com/api/v3/simple/price?ids=bitcoin&vs_currencies=usd',
    jsonSelector: 'bitcoin.usd',
    recommendedBandBps: 100,
    thresholdPlaceholder: '110000',
  },
  {
    id: 'espn',
    label: 'ESPN (sports score)',
    description:
      "Live game score from ESPN. Best for final-score markets — check the selector matches your sport's API response shape.",
    dataSource:
      'https://site.api.espn.com/apis/site/v2/sports/basketball/nba/scoreboard',
    jsonSelector: 'events.0.competitions.0.competitors.0.score',
    recommendedBandBps: 300,
    thresholdPlaceholder: '21',
  },
  {
    id: 'custom',
    label: 'Custom (free-form)',
    description: 'Any JSON endpoint. Paste the URL and selector yourself.',
    dataSource: '',
    jsonSelector: '',
    recommendedBandBps: 100,
  },
];

export function getTemplateById(id: MarketTemplate['id']): MarketTemplate | undefined {
  return TEMPLATES.find((t) => t.id === id);
}
