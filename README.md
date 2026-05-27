# Somi — Autonomous AI-Resolved Prediction Markets on Somnia Agentic L1

Somi is a prediction market platform where every market is resolved autonomously by an AI agent, with verdicts anchored on-chain via the Somnia Agents platform. No human moderators. No off-chain oracles. The agent calls it — on-chain, verifiably, every time.

Built on [Somnia Agentic L1](https://docs.somnia.network) — a high-throughput EVM chain purpose-built for agent-native applications.

## Project Structure

```
contracts/   Foundry smart contracts (Solidity 0.8.30, OpenZeppelin v5)
frontend/    Next.js 16 frontend (Tailwind v4, shadcn/ui, wagmi v2)
```

## Setup

### 1. Contracts

```bash
cd contracts
forge build
```

Requires [Foundry](https://book.getfoundry.sh/getting-started/installation). On a clean checkout this takes under 10 minutes.

### 2. Frontend

```bash
cd frontend
pnpm install
pnpm dev
```

Requires [pnpm](https://pnpm.io/installation). Open [http://localhost:3000](http://localhost:3000).

## Key Management

Private keys must **never** appear in `.env`, `.env.example`, or any committed file.
Foundry's encrypted keystore is the only accepted mechanism for signing transactions:

```bash
cast wallet import somi-deployer --interactive
```

You will be prompted for your Somnia testnet private key and a password. The encrypted keystore is stored at `~/.foundry/keystores/somi-deployer` and is **never committed**.

## On the Somnia Prototype

Somnia Agent receipts are currently stored on centralised infrastructure operated by the Somnia Foundation. This is a known limitation of the Agentathon prototype (AR-22 I1, NFR-6). A decentralised receipt layer is on the roadmap.

## Planning Artifacts

- PRD: [`_bmad-output/planning-artifacts/prds/prd-Somi-2026-05-25/prd.md`](_bmad-output/planning-artifacts/prds/prd-Somi-2026-05-25/prd.md)
- Architecture: [`_bmad-output/planning-artifacts/architecture.md`](_bmad-output/planning-artifacts/architecture.md)
- UX Design: [`_bmad-output/planning-artifacts/ux-design-specification.md`](_bmad-output/planning-artifacts/ux-design-specification.md)
