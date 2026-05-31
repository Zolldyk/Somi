const rawContractAddress = process.env.NEXT_PUBLIC_CONTRACT_ADDRESS;
export const CONTRACT_ADDRESS: `0x${string}` | undefined =
  rawContractAddress && /^0x[0-9a-fA-F]{40}$/.test(rawContractAddress)
    ? (rawContractAddress as `0x${string}`)
    : undefined;

export const RECEIPT_BASE_URL = 'https://agents.testnet.somnia.network/receipts/' as const;

export const MIN_BET_STT = 0.01 as const;

const rawFeaturedMarketId = process.env.NEXT_PUBLIC_FEATURED_MARKET_ID;
export const FEATURED_MARKET_ID: bigint | undefined =
  rawFeaturedMarketId && /^\d+$/.test(rawFeaturedMarketId)
    ? BigInt(rawFeaturedMarketId)
    : undefined;
