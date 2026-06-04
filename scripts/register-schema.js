// Compute and register the Somi market-outcome schema on Somnia Streams.
// Usage: node register-schema.js
//
// Phase 1 (read-only): computes and prints the schema ID.
// Phase 2 (wallet): registers the schema. Prompts for your private key — never stored.

'use strict';

const { createPublicClient, createWalletClient, http, defineChain } = require('viem');
const { privateKeyToAccount } = require('viem/accounts');
const { SDK } = require('@somnia-chain/streams');
const readline = require('readline');

const SOMNIA_TESTNET = defineChain({
  id: 50312,
  name: 'Somnia Testnet',
  nativeCurrency: { name: 'STT', symbol: 'STT', decimals: 18 },
  rpcUrls: { default: { http: ['https://api.infra.testnet.somnia.network'] } },
});

const SCHEMA = 'uint256 marketId, string question, uint8 verdict, uint64 resolvedAt, uint256 requestId';
const SCHEMA_NAME = 'somi-market-outcome';
const ZERO_BYTES32 = '0x' + '00'.repeat(32);

function prompt(question) {
  const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
  return new Promise((resolve) => {
    // Hide input for the private key
    process.stdout.write(question);
    process.stdin.setRawMode && process.stdin.setRawMode(true);
    let input = '';
    process.stdin.resume();
    process.stdin.setEncoding('utf8');
    const onData = (char) => {
      if (char === '\n' || char === '\r') {
        process.stdin.setRawMode && process.stdin.setRawMode(false);
        process.stdin.removeListener('data', onData);
        process.stdout.write('\n');
        rl.close();
        resolve(input);
      } else if (char === '') {
        process.exit();
      } else {
        input += char;
        process.stdout.write('*');
      }
    };
    process.stdin.on('data', onData);
  });
}

async function main() {
  const publicClient = createPublicClient({
    chain: SOMNIA_TESTNET,
    transport: http(),
  });

  const readSdk = new SDK({ public: publicClient });

  // ── Phase 1: Compute schema ID (read-only) ──────────────────────────────
  console.log('\n[1/3] Computing schema ID on-chain (read-only)...');
  console.log(`      Schema: ${SCHEMA}`);

  const schemaId = await readSdk.streams.computeSchemaId(SCHEMA);
  if (schemaId instanceof Error) {
    console.error('Failed to compute schema ID:', schemaId.message);
    process.exit(1);
  }
  console.log(`\n✓ STREAMS_SCHEMA_ID = ${schemaId}\n`);

  // ── Check if already registered ─────────────────────────────────────────
  console.log('[2/3] Checking if schema is already registered...');
  const isRegistered = await readSdk.streams.isDataSchemaRegistered(schemaId);
  if (isRegistered instanceof Error) {
    console.error('Failed to check registration:', isRegistered.message);
    process.exit(1);
  }

  if (isRegistered) {
    console.log('✓ Schema already registered — no transaction needed.\n');
    console.log('Update PredictionMarket.sol:106 to:');
    console.log(`  bytes32 private constant STREAMS_SCHEMA_ID = ${schemaId}; // [Epic 5]`);
    return;
  }

  console.log('  Schema not yet registered.\n');

  // ── Phase 2: Register (wallet required) ─────────────────────────────────
  console.log('[3/3] Registering schema (requires somi-deployer private key).');
  console.log('      Key is used in memory only and never written to disk.\n');
  console.log('      Tip: get your key with:');
  console.log('        cast wallet export --account somi-deployer --json\n');

  let privateKey = await prompt('Private key (0x...): ');
  privateKey = privateKey.trim();
  if (!privateKey.startsWith('0x')) privateKey = '0x' + privateKey;

  const account = privateKeyToAccount(privateKey);
  console.log(`\n  Signing as: ${account.address}`);

  const walletClient = createWalletClient({
    account,
    chain: SOMNIA_TESTNET,
    transport: http(),
  });

  const writeSdk = new SDK({ public: publicClient, wallet: walletClient });

  const txHash = await writeSdk.streams.registerDataSchemas([{
    schemaName: SCHEMA_NAME,
    schema: SCHEMA,
    parentSchemaId: ZERO_BYTES32,
  }]);

  if (txHash instanceof Error) {
    console.error('\nRegistration failed:', txHash.message);
    process.exit(1);
  }

  console.log(`\n✓ Schema registered! Tx: ${txHash}`);
  console.log('\n══════════════════════════════════════════════════════════');
  console.log('Next steps:');
  console.log(`  1. Update contracts/src/PredictionMarket.sol:106:`);
  console.log(`       bytes32 private constant STREAMS_SCHEMA_ID = ${schemaId}; // [Epic 5]`);
  console.log(`  2. Redeploy PredictionMarket (forge create)`);
  console.log(`  3. Update frontend/.env.local NEXT_PUBLIC_CONTRACT_ADDRESS`);
  console.log(`  4. Deploy MarketOutcomeSubscriber with:`);
  console.log(`       --constructor-args 0x6AB397FF662e42312c003175DCD76EfF69D048Fc ${schemaId}`);
  console.log('══════════════════════════════════════════════════════════\n');
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
