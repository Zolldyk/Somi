// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {CommonBase} from "forge-std/Base.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {StdUtils} from "forge-std/StdUtils.sol";
import {PredictionMarket} from "../src/PredictionMarket.sol";
import {MarketStatus, Verdict, AgentRequestType} from "../src/libraries/MarketLib.sol";
import {ISomniaAgents} from "../src/interfaces/ISomniaAgents.sol";
import {MockSomniaAgents} from "./mocks/MockSomniaAgents.sol";
import {MockSomniaReactivityPrecompile} from "./mocks/MockSomniaReactivityPrecompile.sol";
import {ISomniaReactivityPrecompile} from
    "@somnia-chain/reactivity-contracts/contracts/interfaces/ISomniaReactivityPrecompile.sol";

// ============================================================
//  Handler — defines all valid state-transition actions
// ============================================================

contract PredictionMarketHandler is CommonBase, StdCheats, StdUtils {
    PredictionMarket internal s_pm;
    MockSomniaAgents internal s_mockAgents;
    address private constant PRECOMPILE = address(0x0100);

    // Ghost variables — tracked across all handler calls
    uint256 public ghost_totalBets;
    uint256 public ghost_totalClaimed;
    uint256 public ghost_totalRefunded;

    // Market tracking (bounded list)
    uint256[] internal s_marketIds;

    // Terminal-state tracking (for StateMonotonicity invariant)
    mapping(uint256 => bool) internal s_wasTerminal;

    // Claim/refund tracking (for ClaimedAndRefundedAreExclusive invariant)
    mapping(uint256 => mapping(address => bool)) internal s_hasClaimed;
    mapping(uint256 => mapping(address => bool)) internal s_hasRefunded;

    // Bounded actor set — 4 addresses cover combinatorial space adequately
    address[] internal s_actors;

    uint256 private constant MIN_BET = 0.01 ether;
    uint256 private constant MIN_LEAD_TIME = 5 minutes;

    constructor(PredictionMarket pm, MockSomniaAgents mockAgents) {
        s_pm = pm;
        s_mockAgents = mockAgents;
        s_actors.push(address(0x1001));
        s_actors.push(address(0x1002));
        s_actors.push(address(0x1003));
        s_actors.push(address(0x1004));
    }

    // --- Accessor helpers for invariant assertions ---

    function marketCount() external view returns (uint256) {
        return s_marketIds.length;
    }

    function marketIdAt(uint256 i) external view returns (uint256) {
        return s_marketIds[i];
    }

    function wasTerminal(uint256 mid) external view returns (bool) {
        return s_wasTerminal[mid];
    }

    function hasClaimed(uint256 mid, address a) external view returns (bool) {
        return s_hasClaimed[mid][a];
    }

    function hasRefunded(uint256 mid, address a) external view returns (bool) {
        return s_hasRefunded[mid][a];
    }

    function actorCount() external view returns (uint256) {
        return s_actors.length;
    }

    function actorAt(uint256 i) external view returns (address) {
        return s_actors[i];
    }

    // --- Handler actions ---

    function createMarket(uint256 futureOffset, uint256 threshold, uint256 bandBps) external {
        futureOffset = bound(futureOffset, MIN_LEAD_TIME + 1, 365 days);
        threshold = bound(threshold, 1, 1e18);
        bandBps = bound(bandBps, 1, 1000);
        uint64 resolutionTime = uint64(block.timestamp + futureOffset);

        try s_pm.createMarket(
            "Will result exceed threshold?",
            "https://api.example.com/data",
            "result.value",
            threshold,
            resolutionTime,
            bandBps
        ) returns (uint256 marketId) {
            s_marketIds.push(marketId);
        } catch {}
    }

    function placeBet(uint256 actorSeed, uint256 midSeed, uint8 side, uint256 amount) external {
        if (s_marketIds.length == 0) return;
        address actor = s_actors[bound(actorSeed, 0, s_actors.length - 1)];
        uint256 mid = s_marketIds[bound(midSeed, 0, s_marketIds.length - 1)];
        side = uint8(bound(side, 0, 1));
        amount = bound(amount, MIN_BET, 5 ether);

        // Additive deal: preserve any claimed/refunded ETH the actor already holds
        vm.deal(actor, actor.balance + amount);

        vm.prank(actor);
        try s_pm.placeBet{value: amount}(mid, side) {
            ghost_totalBets += amount;
        } catch {}
    }

    function triggerResolution(uint256 midSeed) external {
        if (s_marketIds.length == 0) return;
        uint256 mid = s_marketIds[bound(midSeed, 0, s_marketIds.length - 1)];

        PredictionMarket.Market memory m = s_pm.getMarket(mid);
        if (m.status != MarketStatus.Open) return;
        if (m.subscriptionId == 0) return;

        bytes32[] memory topics = new bytes32[](2);
        topics[0] = ISomniaReactivityPrecompile.Schedule.selector;
        topics[1] = bytes32(uint256(m.resolutionTime) * 1000 + 777);

        vm.prank(PRECOMPILE);
        try s_pm.onEvent(PRECOMPILE, topics, "") {
            _updateTerminal(mid);
        } catch {}
    }

    function respondJson(uint256 midSeed, uint256 fetchedValue) external {
        if (s_marketIds.length == 0) return;
        uint256 mid = s_marketIds[bound(midSeed, 0, s_marketIds.length - 1)];

        PredictionMarket.Market memory m = s_pm.getMarket(mid);
        if (m.status != MarketStatus.Resolving) return;
        if (m.pendingRequestId == 0) return;

        ISomniaAgents.Response[] memory responses = new ISomniaAgents.Response[](1);
        responses[0] = ISomniaAgents.Response({result: abi.encode(fetchedValue)});
        ISomniaAgents.Request memory req = ISomniaAgents.Request({payload: ""});

        try s_mockAgents.callHandleResponse(m.pendingRequestId, responses, ISomniaAgents.ResponseStatus.Success, req) {
            _updateTerminal(mid);
        } catch {}
    }

    function respondLlm(uint256 midSeed, uint8 verdictSeed) external {
        if (s_marketIds.length == 0) return;
        uint256 mid = s_marketIds[bound(midSeed, 0, s_marketIds.length - 1)];

        PredictionMarket.Market memory m = s_pm.getMarket(mid);
        if (m.status != MarketStatus.LLMResolving) return;
        if (m.pendingRequestId == 0) return;

        // 0 → YES, 1 → NO, 2 → INVALID (rotate through all three verdicts)
        string memory verdict;
        if (verdictSeed % 3 == 0) verdict = "YES";
        else if (verdictSeed % 3 == 1) verdict = "NO";
        else verdict = "INVALID";

        ISomniaAgents.Response[] memory responses = new ISomniaAgents.Response[](1);
        responses[0] = ISomniaAgents.Response({result: abi.encode(verdict)});
        ISomniaAgents.Request memory req = ISomniaAgents.Request({payload: ""});

        try s_mockAgents.callHandleResponse(m.pendingRequestId, responses, ISomniaAgents.ResponseStatus.Success, req) {
            _updateTerminal(mid);
        } catch {}
    }

    function simulateAgentFailure(uint256 midSeed, uint8 failStatusSeed) external {
        if (s_marketIds.length == 0) return;
        uint256 mid = s_marketIds[bound(midSeed, 0, s_marketIds.length - 1)];

        PredictionMarket.Market memory m = s_pm.getMarket(mid);
        if (m.status != MarketStatus.Resolving && m.status != MarketStatus.LLMResolving) return;
        if (m.pendingRequestId == 0) return;

        // Alternate between Failed (1) and TimedOut (2)
        ISomniaAgents.ResponseStatus failStatus =
            failStatusSeed % 2 == 0 ? ISomniaAgents.ResponseStatus.Failed : ISomniaAgents.ResponseStatus.TimedOut;

        ISomniaAgents.Response[] memory responses = new ISomniaAgents.Response[](0);
        ISomniaAgents.Request memory req = ISomniaAgents.Request({payload: ""});

        try s_mockAgents.callHandleResponse(m.pendingRequestId, responses, failStatus, req) {
            _updateTerminal(mid);
        } catch {}
    }

    function claim(uint256 actorSeed, uint256 midSeed) external {
        if (s_marketIds.length == 0) return;
        address actor = s_actors[bound(actorSeed, 0, s_actors.length - 1)];
        uint256 mid = s_marketIds[bound(midSeed, 0, s_marketIds.length - 1)];

        uint256 before = actor.balance;

        vm.prank(actor);
        try s_pm.claim(mid) {
            ghost_totalClaimed += actor.balance - before;
            s_hasClaimed[mid][actor] = true;
        } catch {}
    }

    function refund(uint256 actorSeed, uint256 midSeed) external {
        if (s_marketIds.length == 0) return;
        address actor = s_actors[bound(actorSeed, 0, s_actors.length - 1)];
        uint256 mid = s_marketIds[bound(midSeed, 0, s_marketIds.length - 1)];

        uint256 before = actor.balance;

        vm.prank(actor);
        try s_pm.refund(mid) {
            ghost_totalRefunded += actor.balance - before;
            s_hasRefunded[mid][actor] = true;
        } catch {}
    }

    // --- Internal helpers ---

    function _updateTerminal(uint256 mid) internal {
        PredictionMarket.Market memory m = s_pm.getMarket(mid);
        if (m.status == MarketStatus.Resolved || m.status == MarketStatus.Refunded || m.status == MarketStatus.Disputed)
        {
            s_wasTerminal[mid] = true;
        }
    }
}

// ============================================================
//  Invariant test suite
// ============================================================

contract PredictionMarketInvariantsTest is StdInvariant, Test {
    PredictionMarket private s_pm;
    MockSomniaAgents private s_mockAgents;
    PredictionMarketHandler private s_handler;
    address private constant PRECOMPILE = address(0x0100);

    uint256 private s_initialDeposit;

    function setUp() public {
        // Etch mock precompile at 0x0100 (unit-test mode — no Somnia fork)
        if (PRECOMPILE.code.length == 0) {
            address mockPc = address(new MockSomniaReactivityPrecompile());
            vm.etch(PRECOMPILE, mockPc.code);
        }

        // Deploy contracts
        s_mockAgents = new MockSomniaAgents(address(0));
        // 500 ether: large enough for 1300+ agent-deposit rounds (0.36 STT each)
        s_pm = new PredictionMarket{value: 500 ether}(address(s_mockAgents));
        s_mockAgents.setTarget(address(s_pm));

        s_initialDeposit = address(s_pm).balance; // 500 ether

        // Deploy handler; target only handler (not PM directly — handler gates valid transitions)
        s_handler = new PredictionMarketHandler(s_pm, s_mockAgents);
        targetContract(address(s_handler));
    }

    /// @notice Total ETH entering system equals total ETH still in system plus total ETH paid out.
    /// @dev LHS: ETH still held by PM + ETH held by MockAgents (deposits) + ETH paid to claimants + ETH paid to refundees
    ///      RHS: initial 500 ether + all bets placed
    ///      Invariant holds because all ETH paths are tracked: bets in → ghost_totalBets;
    ///      claims/refunds out → ghost_totalClaimed/Refunded; agent deposits → in mockAgents.balance.
    function invariant_PotConservation() public view {
        uint256 lhs = address(s_pm).balance + address(s_mockAgents).balance + s_handler.ghost_totalClaimed()
            + s_handler.ghost_totalRefunded();
        uint256 rhs = s_initialDeposit + s_handler.ghost_totalBets();
        assertEq(lhs, rhs, "pot conservation violated: ETH created or destroyed");
    }

    /// @notice Markets never transition out of terminal states (Resolved, Refunded, Disputed).
    function invariant_StateMonotonicity() public view {
        uint256 count = s_handler.marketCount();
        for (uint256 i; i < count; i++) {
            uint256 mid = s_handler.marketIdAt(i);
            if (!s_handler.wasTerminal(mid)) continue;
            PredictionMarket.Market memory m = s_pm.getMarket(mid);
            assertTrue(
                m.status == MarketStatus.Resolved || m.status == MarketStatus.Refunded
                    || m.status == MarketStatus.Disputed,
                "terminal market escaped to non-terminal state"
            );
        }
    }

    /// @notice No address can both claim and refund the same market.
    function invariant_ClaimedAndRefundedAreExclusive() public view {
        uint256 midCount = s_handler.marketCount();
        uint256 actorCount = s_handler.actorCount();
        for (uint256 i; i < midCount; i++) {
            uint256 mid = s_handler.marketIdAt(i);
            for (uint256 j; j < actorCount; j++) {
                address actor = s_handler.actorAt(j);
                assertFalse(
                    s_handler.hasClaimed(mid, actor) && s_handler.hasRefunded(mid, actor),
                    "same address claimed and refunded the same market"
                );
            }
        }
    }
}
