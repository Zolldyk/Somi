// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {PredictionMarket} from "../src/PredictionMarket.sol";

/// @notice Deploys a fresh PredictionMarket. The constructor only sets the
///         immutable Somnia Agents address — it never touches the reactivity
///         precompile — so local script simulation succeeds (unlike createMarket).
contract DeployFresh is Script {
    function run() external {
        address agents = vm.envAddress("SOMNIA_AGENTS_ADDR");
        require(agents != address(0), "SOMNIA_AGENTS_ADDR not set");

        vm.startBroadcast();
        PredictionMarket pm = new PredictionMarket(agents);
        vm.stopBroadcast();

        console.log("PredictionMarket deployed at:", address(pm));
    }
}
