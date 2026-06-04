// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {PredictionMarket} from "../src/PredictionMarket.sol";

contract SeedDemoMarkets is Script {
    function run() external {
        address pmAddr = vm.envAddress("PM_ADDRESS");
        require(pmAddr != address(0), "PM_ADDRESS not set");
        require(
            pmAddr.balance >= 32 ether,
            "PM contract underfunded; run `cast send <pm> --value 35ether --legacy` first"
        );
        PredictionMarket pm = PredictionMarket(payable(pmAddr));

        console.log("Contract balance (wei):", pmAddr.balance);

        // --- Threshold env vars (override via env for demo tuning) ---
        uint256 btcThreshold     = vm.envOr("SEED_BTC_THRESHOLD",      uint256(105_000));
        uint256 sportsThreshold  = vm.envOr("SEED_SPORTS_THRESHOLD",   uint256(100));
        uint256 wildThreshold    = vm.envOr("SEED_WILDCARD_THRESHOLD", uint256(150));

        // --- Hour offsets (resolution time = now + offset) ---
        // Crypto default 3h so the README "≥2h, ≤4h before recording" window has headroom.
        // Wildcard default 3h so SOL has a low probability of leaving the 10% ambiguity band.
        uint256 cryptoOffsetH = vm.envOr("SEED_CRYPTO_OFFSET_HOURS",   uint256(3));
        uint256 sportsOffsetH = vm.envOr("SEED_SPORTS_OFFSET_HOURS",   uint256(6));
        uint256 wildOffsetH   = vm.envOr("SEED_WILDCARD_OFFSET_HOURS", uint256(3));

        uint64 cryptoResolution = uint64(block.timestamp + cryptoOffsetH * 1 hours);
        uint64 sportsResolution = uint64(block.timestamp + sportsOffsetH * 1 hours);
        uint64 wildResolution   = uint64(block.timestamp + wildOffsetH   * 1 hours);

        vm.startBroadcast();

        // Beat 4: Crypto — BTC/USD via CoinGecko; 100 bps band; threshold ~$105k → resolves YES at ~$108k+
        uint256 cryptoId = pm.createMarket(
            "Will BTC close above $105,000 USD at resolution?",
            "https://api.coingecko.com/api/v3/simple/price?ids=bitcoin&vs_currencies=usd",
            "bitcoin.usd",
            btcThreshold,
            cryptoResolution,
            100 // 1% ambiguity band
        );

        // Sports — ESPN NBA scoreboard. Selector reads the first-listed competitor of the first event;
        // question wording matches that data path verbatim (no "leading team" framing) so the question
        // text and the resolution data line up.
        uint256 sportsId = pm.createMarket(
            "Will the first-listed team in tonight's NBA game score above 100 points?",
            "https://site.api.espn.com/apis/site/v2/sports/basketball/nba/scoreboard",
            "events.0.competitions.0.competitors.0.score",
            sportsThreshold,
            sportsResolution,
            300 // 3% ambiguity band
        );

        // Beat 5: Wildcard — SOL/USD via CoinGecko. Set SEED_WILDCARD_THRESHOLD to current spot SOL
        // before running (README has a curl one-liner). 10% band + 3h horizon gives high probability
        // of in-band landing → LLM tiebreaker fires; the vague "decisive directional move" wording is
        // what then triggers an INVALID verdict.
        uint256 wildId = pm.createMarket(
            "Will SOL make a decisive directional move above its seeding price by resolution?",
            "https://api.coingecko.com/api/v3/simple/price?ids=solana&vs_currencies=usd",
            "solana.usd",
            wildThreshold,
            wildResolution,
            1000 // 10% ambiguity band (contract max) — engineered to land in band and trigger INVALID
        );

        vm.stopBroadcast();

        console.log("=== Demo Market IDs ===");
        console.log("Crypto  (Beat 4):", cryptoId);
        console.log("Sports          :", sportsId);
        console.log("Wildcard (Beat 5):", wildId);
        console.log("Copy this marketId into NEXT_PUBLIC_FEATURED_MARKET_ID:", cryptoId);
    }
}
