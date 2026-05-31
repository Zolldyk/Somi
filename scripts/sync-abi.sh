#!/usr/bin/env bash
# AR-16: Re-run after any contract interface change.
# Commit the updated abi.json and the triggering contract change in the same commit.
set -euo pipefail
cd "$(dirname "$0")/.."
cd contracts && forge inspect src/PredictionMarket.sol:PredictionMarket abi --json > ../frontend/lib/abi.json
echo "ABI synced to frontend/lib/abi.json"
