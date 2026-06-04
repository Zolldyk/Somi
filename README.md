# Somi: Autonomous AI-Resolved Prediction Markets on Somnia Agentic L1

Somi is a binary prediction market where every outcome is resolved autonomously by an AI agent — the agent fetches live data, evaluates the question, and settles the contract on-chain with no human moderators and no off-chain oracles. The agent shows its work: reasoning is anchored via Somnia Agents so resolution decisions are transparent and publicly verifiable. Built as a showcase of Somnia's Agentic L1 primitives, Somi demonstrates that resolution trust can transfer from institutions to auditable, on-chain AI inference.

## What You'll Need

- [Node 20+](https://nodejs.org)
- [pnpm](https://pnpm.io/installation)
- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- Somnia Testnet STT — get from the [faucet](https://testnet.somnia.network) (requires Twitter/X auth)
- MetaMask configured for Somnia Testnet:

| Field | Value |
|---|---|
| Network Name | Somnia Testnet |
| RPC URL | https://api.infra.testnet.somnia.network |
| Chain ID | 50312 |
| Currency Symbol | STT |
| Block Explorer | https://shannon-explorer.somnia.network |

## Quick Start

**From `git clone` to your first market in ≤10 minutes.**

**1. Clone the repo**

```bash
git clone https://github.com/Zolldyk/Somi && cd Somi
```

**2. Install and build contracts** (~3 min on first run)

```bash
cd contracts && forge install && forge build
```

**3. Configure the contracts environment**

```bash
cp contracts/.env.example contracts/.env
```

`SOMNIA_TESTNET_RPC` is pre-set. Open `contracts/.env` and fill in:

```
SOMNIA_AGENTS_ADDR=0x037Bb9C718F3f7fe5eCBDB0b600D607b52706776
```

**4. Import your deployer key into Foundry's encrypted keystore**

```bash
cast wallet import somi-deployer --interactive
```

Your private key stays local in Foundry's encrypted keystore and is never written to `.env`.

**5. Deploy to Somnia Testnet**

```bash
cd contracts

forge create \
  --account somi-deployer \
  --rpc-url $SOMNIA_TESTNET_RPC \
  --broadcast \
  --legacy \
  --gas-limit 30000000 \
  --value 35ether \
  src/PredictionMarket.sol:PredictionMarket \
  --constructor-args $SOMNIA_AGENTS_ADDR
```

Required flags: `--legacy` (Somnia testnet has no EIP-1559 support), `--gas-limit 30000000` (default gas limit fails on this contract's complexity), `--value 35ether` (seeds the Reactivity precompile balance).

> **Somnia testnet note:** `msg.value` during contract creation is not always credited to the contract's balance on Somnia testnet. After deploy, fund the contract separately so `createMarket` can charge the Reactivity precompile:
>
> ```bash
> cast send <DEPLOYED_ADDRESS> \
>   --account somi-deployer \
>   --rpc-url $SOMNIA_TESTNET_RPC \
>   --value 35ether \
>   --legacy
> ```

**6. Sync the ABI to the frontend**

```bash
forge inspect src/PredictionMarket.sol:PredictionMarket abi --json > ../frontend/lib/abi.json
```

**7. Configure the frontend** (~2 min to create a free WalletConnect account)

```bash
cp frontend/.env.example frontend/.env.local
```

Open `frontend/.env.local` and fill in:

```
NEXT_PUBLIC_CONTRACT_ADDRESS=<deployed_address>
NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID=<your_project_id>
```

Create a free WalletConnect project at [cloud.walletconnect.com](https://cloud.walletconnect.com) to get your project ID.

**8. Start the frontend**

```bash
cd frontend && pnpm install && pnpm dev
```

Open [http://localhost:3000](http://localhost:3000) and create your first market.

## Project Structure

```
contracts/      Foundry smart contracts (Solidity 0.8.30, OpenZeppelin v5)
frontend/       Next.js 16 frontend (Tailwind v4, shadcn/ui, wagmi v2)
scripts/        Utility scripts (ABI sync, schema registration)
_bmad-output/   Project planning artifacts, epics, and story specs
```

For deeper detail, see [`contracts/README.md`](contracts/README.md) and [`frontend/README.md`](frontend/README.md).

## Architecture

[`_bmad-output/planning-artifacts/architecture.md`](_bmad-output/planning-artifacts/architecture.md)

## On the Somnia Prototype

**(a)** Somnia Agents is prototype-stage infrastructure. The `handleResponse` callback interface and `SOMNIA_AGENTS_ADDR` are subject to change before mainnet. The address `0x037Bb9C718F3f7fe5eCBDB0b600D607b52706776` is the testnet value from Somnia's verified research documentation (§12).

**(b)** Somnia Agent receipts are currently stored on centralised infrastructure operated by the Somnia Foundation. This is a known limitation of the Agentathon prototype (AR-22 I1, NFR-6). A decentralised receipt layer is on the roadmap.

**(c)** The Somnia Streams API changed in April 2026. The `registerDataSchemas` call shape changed from `{ id, schema }` to `{ schemaName, schema, parentSchemaId }`. Earlier tutorials online are outdated. See [`contracts/README.md`](contracts/README.md) §"Epic 5 — Outcome Publication" for the current shape.

**(d)** All contract addresses (Agents, Streams proxy) are pinned to the values from Somnia's verified research §12. Do not update these without verifying against official Somnia documentation — the wrong address silently fails.

## Demo Video

_Link added after Story 6.6 recording session._

## License

MIT

---

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

## Frontend Deployment

```bash
cd frontend
vercel link    # one-time
vercel --prod  # subsequent deploys (or auto on git push to main)
```
