# Somi — Frontend

Next.js 16 frontend for the Somi autonomous AI-resolved prediction market on Somnia Agentic L1.

## Prerequisites

- Node.js 20+
- [pnpm](https://pnpm.io/installation)

## Setup

```bash
pnpm install
cp .env.example .env.local
# Edit .env.local — set NEXT_PUBLIC_CONTRACT_ADDRESS after deploying contracts
```

## Environment Variables

See `.env.example` for the full list. All variables are public (`NEXT_PUBLIC_*`) — no secrets belong here.

| Variable | Description |
|---|---|
| `NEXT_PUBLIC_CONTRACT_ADDRESS` | Deployed PredictionMarket contract address |
| `NEXT_PUBLIC_RPC_URL` | Somnia testnet RPC (default provided) |
| `NEXT_PUBLIC_FEATURED_MARKET_ID` | Market ID shown in the featured slot on home page |

## Development

```bash
pnpm dev
```

## Build

```bash
pnpm build
```

## Stack

- Next.js 16 + TypeScript (strict)
- Tailwind CSS v4
- shadcn/ui (radix base)
- wagmi v2 + viem v2 + RainbowKit v2 + TanStack Query
