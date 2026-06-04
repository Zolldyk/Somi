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
