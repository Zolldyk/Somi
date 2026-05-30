# Somi: Autonomous AI-Resolved Prediction Markets on Somnia Agentic L1

Somi is a prediction market platform where every market is resolved autonomously by an AI agent, with verdicts anchored on-chain via the Somnia Agents platform. No human moderators. No off-chain oracles. The agent calls it and the activities remain verifiably on-chain every time.

Built on [Somnia Agentic L1](https://docs.somnia.network). Somnia is a high-throughput EVM chain purpose-built for agent-native applications.

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

## Contracts — Testing & Coverage

```bash
# Unit + fuzz tests
cd contracts && forge test

# Invariant tests only
cd contracts && forge test --match-contract PredictionMarketInvariantsTest -v

# All tests including invariants
cd contracts && forge test -v

# Coverage report (target: ≥90% line + branch for all src/ files)
cd contracts && forge coverage --report summary

# Static analysis (target: zero HIGH/MEDIUM findings)
cd contracts && slither src/
```

## Deployment

### Contract → Somnia Testnet (chain 50312)

```bash
export SOMNIA_TESTNET_RPC=https://api.infra.testnet.somnia.network
export SOMNIA_AGENTS_ADDR=0x037Bb9C718F3f7fe5eCBDB0b600D607b52706776

cd contracts && forge create \
  --account somi-deployer \
  --rpc-url $SOMNIA_TESTNET_RPC \
  --broadcast \
  --value 50ether \
  src/PredictionMarket.sol:PredictionMarket \
  --constructor-args $SOMNIA_AGENTS_ADDR
```

After deploy, copy the deployed address to `frontend/.env.local`:

```
NEXT_PUBLIC_CONTRACT_ADDRESS=<deployed_address>
```

### ABI Sync

Re-run after any contract interface change (AR-16 discipline — commit ABI and contract source together):

```bash
cd contracts && forge inspect src/PredictionMarket.sol:PredictionMarket abi --json > ../frontend/lib/abi.json
```

### Frontend → Vercel

```bash
cd frontend
vercel link    # one-time
vercel --prod  # subsequent deploys (or auto on git push to main)
```

## Key Management

Private keys must **never** appear in `.env`, `.env.example`, or any committed file.
Foundry's encrypted keystore is the only accepted mechanism for signing transactions:

```bash
cast wallet import somi-deployer --interactive
```

You will be prompted for your Somnia testnet private key and a password. 

## On the Somnia Prototype

Somnia Agent receipts are currently stored on centralised infrastructure operated by the Somnia Foundation. This is a known limitation of the Agentathon prototype (AR-22 I1, NFR-6). A decentralised receipt layer is on the roadmap.
