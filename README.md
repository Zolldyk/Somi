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

Each step below runs from the **repo root** (return there at the end of any step that `cd`s elsewhere).

**1. Clone the repo with submodules**

```bash
git clone --recurse-submodules https://github.com/Zolldyk/Somi && cd Somi
```

`--recurse-submodules` is required — the repo depends on `forge-std` and `openzeppelin-contracts` as git submodules. If you already cloned without it, run `git submodule update --init --recursive` from the repo root.

**2. Build the contracts** (~3 min on first run)

```bash
cd contracts && forge build && cd ..
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

If you don't have a deployer key yet, generate one with `cast wallet new` and back up the seed phrase. Then fund the public address from the Somnia faucet (see "What You'll Need") before continuing.

```bash
cast wallet import somi-deployer --interactive
```

Your private key stays local in Foundry's encrypted keystore and is never written to `.env`.

**5. Deploy to Somnia Testnet**

`forge` does not auto-load `.env`, so source it explicitly into the shell first.

```bash
cd contracts
set -a; source .env; set +a

forge create \
  --account somi-deployer \
  --rpc-url $SOMNIA_TESTNET_RPC \
  --broadcast \
  --legacy \
  --gas-limit 30000000 \
  src/PredictionMarket.sol:PredictionMarket \
  --constructor-args $SOMNIA_AGENTS_ADDR

cd ..
```

Required flags: `--legacy` (Somnia testnet has no EIP-1559 support) and `--gas-limit 30000000` (default gas limit fails on this contract's complexity). **Do not pass `--value` here** — `msg.value` is not credited during contract creation on Somnia testnet, so any ETH attached to `forge create` is lost. Fund the contract in the next sub-step.

Capture the deployed address from the `forge create` output — it appears as `Deployed to: 0x…`. You'll need it for the funding `cast send`, for `NEXT_PUBLIC_CONTRACT_ADDRESS` in step 7, and (optionally) for `NEXT_PUBLIC_FEATURED_MARKET_ID` once your first market is created.

> **Fund the contract** so `createMarket` can charge the Reactivity precompile (≥32 STT floor required):
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
cd contracts && forge inspect src/PredictionMarket.sol:PredictionMarket abi --json > ../frontend/lib/abi.json && cd ..
```

**7. Configure the frontend** (~2 min to create a free WalletConnect account — required, not optional)

```bash
cp frontend/.env.example frontend/.env.local
```

Open `frontend/.env.local` and fill in:

```
NEXT_PUBLIC_CONTRACT_ADDRESS=<deployed_address>
NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID=<your_project_id>
```

`NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID` is **mandatory** — without it the app throws on first render. Create a free WalletConnect project at [cloud.walletconnect.com](https://cloud.walletconnect.com) to get the ID.

`NEXT_PUBLIC_FEATURED_MARKET_ID` is optional. Leave it blank for the first run; once you've created a market, paste its ID here to feature it on the homepage.

**8. Start the frontend**

```bash
cd frontend && pnpm install && pnpm dev
```

Open [http://localhost:3000](http://localhost:3000) and create your first market.

## Project Structure

```
contracts/   Foundry smart contracts (Solidity 0.8.30, OpenZeppelin v5)
frontend/    Next.js 16 frontend (Tailwind v4, shadcn/ui, wagmi v2)
scripts/     Utility scripts (ABI sync, schema registration)
```

For deeper detail, see [`contracts/README.md`](contracts/README.md) and [`frontend/README.md`](frontend/README.md).

## Architecture

Somi composes three Somnia primitives into a single autonomous resolution loop:

- **Reactivity** — `createMarket` registers a one-shot `scheduleSubscriptionAtTimestamp` deposit; when the resolution time elapses, Somnia fires `handleResponse` on the contract with no external trigger required.
- **Agents** — the same `handleResponse` callback queries a JSON API agent (`fetchUint`) and, when the result falls inside the ambiguity band, chains an LLM Tiebreaker agent (`inferString` with `allowedValues = ["YES", "NO", "INVALID"]`). Reasoning is anchored in the Somnia Agents receipt.
- **Streams** — on settlement, the contract emits a typed `OutcomePublished` event via the Streams SDK so downstream contracts (e.g. `MarketOutcomeSubscriber`) can compose with outcomes in the same block.

**Stack.** One primary contract (`PredictionMarket.sol`) on Solidity 0.8.30 with OpenZeppelin v5 (`ReentrancyGuard`, custom errors), plus a stretch `MarketOutcomeSubscriber.sol` for the Streams demo. Foundry handles unit, fuzz, and invariant tests (≥90% coverage target). The frontend is Next.js 16 on the App Router with five locked routes (`/`, `/markets/[id]`, `/create`, `/my-bets`, `/about`), viem + wagmi v2 with block-aware reads (no polling), RainbowKit for wallet connection, and Tailwind v4 + shadcn/ui under a single dark-mode theme. No off-chain backend, no database, no oracle.

**State machine.** Markets transition `Open → Resolving → (LLMResolving →) Resolved | Refunded`. `Refunded` covers both `INVALID` verdicts and timed-out callbacks; `INVALID` is treated as a first-class verdict, not an error. The callback validates `msg.sender == SOMNIA_AGENTS` before routing by stored request metadata (`requestId → marketId + agentType`); `claim` and `refund` use `ReentrancyGuard` with the CEI pattern. No admin keys, no upgradeability.

**Deploy targets.** Somnia Testnet (chain 50312) only; Vercel for the frontend. Contract maintains ≥32 STT to cover Reactivity precompile fees per the deploy steps above.

## On the Somnia Prototype

**(a)** Somnia Agents is prototype-stage infrastructure. The `handleResponse` callback interface and `SOMNIA_AGENTS_ADDR` are subject to change before mainnet. The address `0x037Bb9C718F3f7fe5eCBDB0b600D607b52706776` is the current Somnia Testnet value; verify it against the [official Somnia Agents documentation](https://docs.somnia.network) before redeploying.

**(b)** Somnia Agent receipts are currently stored on centralised infrastructure operated by the Somnia Foundation. This is a known limitation of the Agentathon prototype (AR-22 I1, NFR-6). A decentralised receipt layer is on the roadmap.

**(c)** The Somnia Streams API changed in April 2026. The `registerDataSchemas` call shape changed from `{ id, schema }` to `{ schemaName, schema, parentSchemaId }`. Earlier tutorials online are outdated. See [`contracts/README.md`](contracts/README.md) for the current shape.

**(d)** All contract addresses (Agents, Streams proxy) are pinned to the values published in the [official Somnia documentation](https://docs.somnia.network). Do not update these without re-verifying against that source — the wrong address silently fails.

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


