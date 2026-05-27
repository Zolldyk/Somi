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
