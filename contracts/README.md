# Somi — Contracts

Foundry project for the Somi prediction market smart contracts on Somnia Agentic L1.

## Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation) (forge, cast, anvil)
- Somnia testnet STT for deployment gas

## Setup

```bash
cp .env.example .env
# Edit .env — set SOMNIA_TESTNET_RPC (default already set) and SOMNIA_AGENTS_ADDR
```

## Build

```bash
forge build
```

## Test

```bash
forge test
```

## Coverage

```bash
forge coverage
```

## Static Analysis (Slither)

```bash
slither . --config-file slither.config.json
```

## Key Management — Why no private key in `.env`

Private keys must **never** appear in `.env`, `.env.example`, or any committed file (AR-2).
Foundry's encrypted keystore is the only accepted mechanism:

```bash
cast wallet import somi-deployer --interactive
```

You will be prompted for your testnet private key and a password. The key is stored as
encrypted JSON at `~/.foundry/keystores/somi-deployer` — it is never committed.

To deploy using the stored key:

```bash
forge script script/Deploy.s.sol \
  --rpc-url somnia_testnet \
  --account somi-deployer \
  --broadcast
```

Foundry will prompt for your keystore password at deploy time.

## Reactivity Contracts — Vendoring Note

`lib/reactivity-contracts/` is vendored from `npm pack @somnia-chain/reactivity-contracts@0.2.0`
because a public Foundry-installable GitHub mirror does not yet exist (noted as "coming soon"
in Somnia docs as of 2026-05). Once a public mirror is available, replace this vendored copy
with `forge install somnia-chain/reactivity-contracts` and remove the vendored directory.

## Epic 5 — Outcome Publication (STRETCH)

> **Cuttability:** Epic 5 is the first feature to cut per PRD §6.2. To remove it entirely:
> 1. Delete `contracts/src/interfaces/ISomniaStreams.sol`
> 2. Remove the one `import {ISomniaStreams}` line from `PredictionMarket.sol`
> 3. Remove the two `STREAMS_PROXY` and `STREAMS_SCHEMA_ID` constant declarations from `PredictionMarket.sol`
> No other file changes required.

### Schema Definition

After each market settles, the outcome is published to Somnia Streams so any subscriber can
react to verdicts on-chain. The schema string is:

```
'uint256 marketId, string question, uint8 verdict, uint64 resolvedAt, uint256 requestId'
```

Field notes:
- `uint8 verdict` — the `Verdict` enum's underlying type (0=Unset, 1=YES, 2=NO, 3=INVALID)
- `string question` — keep questions short (<200 chars); Somnia Streams docs warn that string
  fields incur on-chain storage costs proportional to length
- `uint256 requestId` — links to the Agent Explorer receipt for cross-referencing
- **Do not reorder fields** — the schema ID is a hash of this exact string; reordering breaks
  all existing subscribers

### Computing the Schema ID (off-chain)

Install the TypeScript SDK once (one-time setup):

```bash
npm i @somnia-chain/streams
```

Then compute the schema ID locally:

```ts
import { SomniaSDK } from '@somnia-chain/streams';

const sdk = new SomniaSDK({ rpc: 'https://dream-rpc.somnia.network' });
const schema = 'uint256 marketId, string question, uint8 verdict, uint64 resolvedAt, uint256 requestId';
const schemaId = await sdk.streams.computeSchemaId(schema);
console.log('STREAMS_SCHEMA_ID =', schemaId); // bytes32 hex string
```

### Registering the Schema on Somnia Testnet (one-time)

> **April 2026 API note:** The `registerDataSchemas` shape changed in April 2026. Earlier tutorials
> use `{ id, schema }` — the current API requires `{ schemaName, schema, parentSchemaId }`.

```ts
import { SomniaSDK } from '@somnia-chain/streams';
import { ethers } from 'ethers';

const provider = new ethers.JsonRpcProvider('https://dream-rpc.somnia.network');
const signer = new ethers.Wallet(process.env.DEPLOYER_PRIVATE_KEY!, provider);
const sdk = new SomniaSDK({ signer });

const zeroBytes32 = '0x' + '00'.repeat(32);
const schema = 'uint256 marketId, string question, uint8 verdict, uint64 resolvedAt, uint256 requestId';

await sdk.streams.registerDataSchemas([{
  schemaName: 'somi-market-outcome',
  schema,
  parentSchemaId: zeroBytes32,
}]);

console.log('Schema registered. Now compute its ID and update STREAMS_SCHEMA_ID.');
```

### Updating `STREAMS_SCHEMA_ID` Before Story 5.2 Ships

After registration, take the `bytes32` value from `computeSchemaId` and update
`PredictionMarket.sol`:

```solidity
bytes32 private constant STREAMS_SCHEMA_ID = 0xYOUR_COMPUTED_ID_HERE; // [Epic 5]
```

Recompile with `forge build` and redeploy before enabling Story 5.2's `_publishOutcome` logic.
Deploying with the `bytes32(0)` placeholder means Story 5.2's `esstores()` call will fail
(submitting a record with schemaId `0x0000...`). The `try/catch` in Story 5.2 ensures this
never reverts settlement — but outcome records will not appear in subscribers.

### Deploy `MarketOutcomeSubscriber`

`MarketOutcomeSubscriber` is an example subscriber that reacts to every Somi settlement via
Reactivity callbacks from the Streams proxy. Deploy it after `PredictionMarket` is live and
the schema ID is known.

> **Somnia CREATE caveat:** `msg.value` is not credited to the contract during `CREATE` on
> Somnia testnet — funding must happen as a separate `cast send` after deployment. Likewise,
> `SomniaExtensions.subscribe()` can't run in the constructor (it requires balance ≥32 STT,
> which the contract doesn't yet have). The subscriber therefore exposes a one-shot
> `subscribe()` external function called after funding.

Three-step deploy:

```bash
# 1. Deploy (no value — would be lost)
forge create --account somi-deployer --rpc-url $SOMNIA_TESTNET_RPC --broadcast --legacy \
  --gas-limit 30000000 \
  src/MarketOutcomeSubscriber.sol:MarketOutcomeSubscriber \
  --constructor-args $STREAMS_PROXY $STREAMS_SCHEMA_ID

# 2. Fund with ≥32 STT (Reactivity precompile minimum balance)
cast send <SUBSCRIBER_ADDRESS> --account somi-deployer --rpc-url $SOMNIA_TESTNET_RPC \
  --value 35ether --legacy

# 3. Register the subscription
cast send <SUBSCRIBER_ADDRESS> "subscribe()" --account somi-deployer \
  --rpc-url $SOMNIA_TESTNET_RPC --legacy --gas-limit 5000000
```

The same caveats apply to `PredictionMarket` itself: deploy with `--gas-limit 30000000 --legacy`,
then fund via `cast send --value 35ether` once deployed.

> **Capture the deployed address** — update `MARKET_OUTCOME_SUBSCRIBER` in your `.env.local`
> for Demo Beat 6 narration.

> **Demo Beat 6 payoff:** After the next market settles, Shannon Explorer will show both
> `MarketResolved` (from `PredictionMarket`) and `OutcomeMirrored` (from `MarketOutcomeSubscriber`)
> in the same block — demonstrating that external contracts can compose with Somi outcomes
> on-chain without any off-chain indexing.

## Demo Run Plan

### Prerequisites

Check the contract has ≥32 STT balance before seeding (createMarket reverts with
`PredictionMarket__InsufficientReactivityFunds` if underfunded):

```bash
cast balance 0xb6824307ba77afF3de9d7899d5Ab6C9cded23546 --rpc-url $SOMNIA_TESTNET_RPC
```

If the balance is low, top it up first:

```bash
cast send 0xb6824307ba77afF3de9d7899d5Ab6C9cded23546 \
  --account somi-deployer \
  --rpc-url $SOMNIA_TESTNET_RPC \
  --value 35ether \
  --legacy
```

### Pre-seed: verify the sports selector resolves

The sports market uses the ESPN scoreboard selector `events.0.competitions.0.competitors.0.score`.
If no NBA game is scheduled in the +6 h window, the `events` array is empty and the agent returns
Failed → market resolves to `Disputed`. Verify there's a live or upcoming game before seeding:

```bash
curl -s "https://site.api.espn.com/apis/site/v2/sports/basketball/nba/scoreboard" \
  | jq '.events | length, .events[0].name'
```

A `0` or empty result means swap to a different sport (`/basketball/wnba/scoreboard` is a safe
in-season fallback) before continuing.

### Pre-seed: capture spot SOL for the wildcard

The wildcard relies on SOL landing inside the threshold's 10 % ambiguity band so the LLM tiebreaker
fires. Pin the threshold to spot SOL at seed time:

```bash
export SEED_WILDCARD_THRESHOLD=$(
  curl -s "https://api.coingecko.com/api/v3/simple/price?ids=solana&vs_currencies=usd" \
    | jq '.solana.usd | floor'
)
echo "Wildcard threshold set to $SEED_WILDCARD_THRESHOLD"
```

### Seeding the demo markets

Run this at least **2 hours** before recording, but **≤4 hours** before — so the crypto market
resolves during the session rather than before you start:

```bash
export PM_ADDRESS=0xb6824307ba77afF3de9d7899d5Ab6C9cded23546
export SOMNIA_TESTNET_RPC=https://api.infra.testnet.somnia.network

forge script script/SeedDemoMarkets.s.sol \
  --account somi-deployer \
  --rpc-url $SOMNIA_TESTNET_RPC \
  --broadcast \
  --legacy \
  --gas-limit 30000000
```

Optional threshold override (BTC default 105 000 — drop it if BTC has moved below):

```bash
# Set comfortably below current price (>2% gap) so Beat 4 resolves YES cleanly
export SEED_BTC_THRESHOLD=103000
```

### After seeding

The script prints the three `marketId` values to stdout:

```
=== Demo Market IDs ===
Crypto  (Beat 4): 7
Sports          : 8
Wildcard (Beat 5): 9
Copy this marketId into NEXT_PUBLIC_FEATURED_MARKET_ID: 7
```

1. Copy the **crypto market's ID** into `frontend/.env.local`:
   ```
   NEXT_PUBLIC_FEATURED_MARKET_ID=<cryptoMarketId>
   ```
2. Redeploy to Vercel (or update the env var in the Vercel dashboard and trigger a redeploy)
   so the FeaturedMarketCard hero slot on the home page shows the live crypto market.

### Recording schedule

| Market | Resolves | Demo beat |
|--------|----------|-----------|
| Crypto (BTC/USD) | +3 h from seeding | Beat 4 — YES resolution |
| Sports (NBA) | +6 h from seeding | Any clean resolution (requires live game in window) |
| Wildcard (SOL/USD) | +3 h from seeding | Beat 5 — INVALID via LLM tiebreaker |

The crypto and wildcard markets both resolve within the recording window. The wildcard relies on
SOL staying inside the ±10 % band of the spot-captured threshold — typically reliable over 3 h, but
if SOL moves more than 10 % during the window the market resolves cleanly and Beat 5 has no LLM
footage.

### Re-seeding (do-over)

Re-run the seeder script at any time — each run creates fresh markets with new `marketId`s. Each
`createMarket` consumes some of the contract's reactivity reserve, so after 2–3 re-seeds top the
contract back up with `cast send <pm> --value 35ether --legacy` to stay above the 32 STT floor.

## Pre-Deploy Checklist

Before pushing to production on Vercel:

1. **Bundle size** — `cd frontend && pnpm build` — confirm the largest route's "First Load JS" is < 700KB (≈ <500KB gzipped per NFR-2). If over budget, run `ANALYZE=true pnpm build` (requires `@next/bundle-analyzer` in devDependencies) to identify contributors.

2. **FMP verification** — After deploying to Vercel, check the Speed Insights tab in the Vercel dashboard. Target: FMP < 2s on cold-start (NFR-2). If FMP > 2s, the most common fix is converting heavy Client Components on the slowest route to Server Components.

3. **Environment variables** — Confirm the required env vars are set in the Vercel dashboard:
   - `NEXT_PUBLIC_CONTRACT_ADDRESS` (required) — the deployed `PredictionMarket` address.
   - `NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID` (required) — the app throws on first render without it.
   - `NEXT_PUBLIC_FEATURED_MARKET_ID` (optional) — set after seeding to feature the crypto market on the homepage.

4. **Smoke test** — After deploy: connect wallet → place bet → confirm the Resolving pipeline strip appears. Verify the Featured market card loads on `/`.
