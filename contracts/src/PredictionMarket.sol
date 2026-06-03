// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

// ============ Imports ============
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SomniaEventHandler} from "@somnia-chain/reactivity-contracts/contracts/SomniaEventHandler.sol";
import {SomniaExtensions} from "@somnia-chain/reactivity-contracts/contracts/interfaces/SomniaExtensions.sol";
import {
    MarketLib,
    MarketStatus,
    Verdict,
    AgentRequestType,
    PredictionMarket__InvalidStateTransition
} from "./libraries/MarketLib.sol";
import {
    SettlementLib,
    PredictionMarket__NotWinningPosition,
    PredictionMarket__NotRefundable
} from "./libraries/SettlementLib.sol";
import {ISomniaAgents} from "./interfaces/ISomniaAgents.sol";
import {ISomniaStreams} from "./interfaces/ISomniaStreams.sol"; // [Epic 5]
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

// Layout of Contract:
// version
// imports
// interfaces, libraries, contracts
// errors
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// external
// public
// internal
// private
// view & pure functions

/**
 * @title PredictionMarket
 * @author Zoll
 * @notice Autonomous AI-resolved binary prediction markets on Somnia Agentic L1
 * @dev Composes Somnia Reactivity (scheduled triggers) + Agents (JSON API + LLM Inference) into a
 *      single autonomous loop. No admin keys; reactivity refills via anonymous receive().
 */
contract PredictionMarket is SomniaEventHandler, ReentrancyGuard {
    // ============ Errors ============

    error PredictionMarket__InvalidThreshold();
    error PredictionMarket__ResolutionTimeInPast();
    error PredictionMarket__EmptyQuestion();
    error PredictionMarket__EmptyDataSource();
    error PredictionMarket__InvalidAmbiguityBand();
    error PredictionMarket__InsufficientReactivityFunds(uint256 available, uint256 required);
    error PredictionMarket__MarketNotOpen();
    error PredictionMarket__MarketDoesNotExist();
    error PredictionMarket__BetBelowMinimum();
    error PredictionMarket__MarketClosed();
    error PredictionMarket__OnlySomniaAgents();
    error PredictionMarket__AlreadyClaimed();
    error PredictionMarket__AlreadyRefunded();
    error PredictionMarket__UnknownRequest();
    error PredictionMarket__InvalidSide();
    error PredictionMarket__TransferFailed();
    error PredictionMarket__ZeroAddress();

    // ============ Type declarations ============

    struct Market {
        uint256 id;
        address creator;
        string question;
        string dataSource;
        string jsonSelector;
        uint256 threshold;
        uint256 ambiguityBandBps;
        uint64 resolutionTime;
        uint256 yesPool;
        uint256 noPool;
        MarketStatus status;
        Verdict verdict;
        uint256 subscriptionId;
        uint256 pendingRequestId;
        AgentRequestType pendingAgentType;
        uint64 resolvedAt;
    }

    // ============ State variables ============

    uint256 private constant MIN_BET = 0.01 ether;
    uint256 private constant RESERVE_FLOOR = 32 ether;
    uint256 private constant LOW_BALANCE_THRESHOLD = 35 ether;
    uint256 private constant MIN_LEAD_TIME = 5 minutes;
    uint256 private constant AMBIGUITY_BAND_MAX_BPS = 1000;
    uint256 private constant BPS_DENOMINATOR = 10000;
    uint256 private constant LLM_DEPOSIT = 0.24 ether;
    uint256 private constant LLM_AGENT_ID = 12847293847561029384;
    uint256 private constant JSON_AGENT_ID = 13174292974160097713;
    uint256 private constant JSON_DEPOSIT = 0.12 ether;
    address private constant STREAMS_PROXY = 0x6AB397FF662e42312c003175DCD76EfF69D048Fc; // [Epic 5]
    bytes32 private constant STREAMS_SCHEMA_ID = bytes32(0); // [Epic 5] placeholder — update after schema registration per README

    address private immutable i_somniaAgents;

    mapping(uint256 => Market) private s_markets;
    mapping(uint256 => mapping(address => mapping(uint8 => uint256))) private s_bets;
    mapping(uint256 => mapping(address => bool)) private s_claimed;
    mapping(uint256 => mapping(address => bool)) private s_refunded;
    mapping(uint256 => uint256) private s_requestToMarket;
    uint256 private s_marketCount;
    mapping(uint256 => uint256) private s_subscriptionToMarket;

    // ============ Events ============

    event MarketCreated(uint256 indexed marketId, address indexed creator, string question, uint64 resolutionTime);
    event ResolutionScheduled(uint256 indexed marketId, uint256 subscriptionId, uint64 resolutionTime);
    event BetPlaced(uint256 indexed marketId, address indexed bettor, uint8 indexed side, uint256 amount);
    event ResolutionInitiated(uint256 indexed marketId, uint256 indexed requestId);
    event ResolutionDeferred(uint256 indexed marketId);
    event ResolutionFailed(uint256 indexed marketId, uint8 status);
    event MarketResolved(
        uint256 indexed marketId, Verdict verdict, uint256 winningPool, uint256 losingPool, uint256 requestId
    );
    event Claimed(uint256 indexed marketId, address indexed bettor, uint256 amount);
    event Refunded(uint256 indexed marketId, address indexed bettor, uint256 amount);
    event StreamsPublishFailed(uint256 indexed marketId, string reason); // [Epic 5]
    event LowReactivityBalance(uint256 currentBalance);

    // ============ Constructor ============

    /**
     * @notice Deploy PredictionMarket, pre-funding it with STT for reactivity subscriptions.
     * @param _somniaAgents Address of the Somnia Agents platform contract.
     * @dev Reverts if msg.value < RESERVE_FLOOR (32 STT). This matches
     *      SomniaExtensions.SUBSCRIPTION_OWNER_MINIMUM_BALANCE (AR-22 C1).
     *      Reactivity top-ups accepted via anonymous receive().
     */
    constructor(address _somniaAgents) payable {
        if (_somniaAgents == address(0)) revert PredictionMarket__ZeroAddress();
        if (msg.value < RESERVE_FLOOR) {
            revert PredictionMarket__InsufficientReactivityFunds(msg.value, RESERVE_FLOOR);
        }
        i_somniaAgents = _somniaAgents;
    }

    /// @notice Accept anonymous STT top-up for reactivity balance (AR-3).
    receive() external payable {}

    // ============ External Functions ============

    /// @notice Register a new binary YES/NO prediction market.
    /// @param question         Human-readable resolution question.
    /// @param dataSource       URL of the JSON API endpoint to query at resolution time.
    /// @param jsonSelector     JSONPath selector to extract the numeric value from the API response.
    /// @param threshold        Numeric boundary (same units as API value) dividing YES from NO.
    /// @param resolutionTime   Unix timestamp (seconds) after which the market may be resolved.
    /// @param ambiguityBandBps Percentage band around threshold (in basis points, 1–1000) triggering LLM tiebreaker.
    /// @return marketId        Monotonically incrementing ID starting at 1.
    /// @dev Reverts: EmptyQuestion | EmptyDataSource | InvalidThreshold | ResolutionTimeInPast |
    ///              InvalidAmbiguityBand | InsufficientReactivityFunds.
    ///      Story 1.11 will wire scheduleSubscriptionAtTimestamp after state writes.
    function createMarket(
        string memory question,
        string memory dataSource,
        string memory jsonSelector,
        uint256 threshold,
        uint64 resolutionTime,
        uint256 ambiguityBandBps
    ) external returns (uint256 marketId) {
        if (bytes(question).length == 0) revert PredictionMarket__EmptyQuestion();
        if (bytes(dataSource).length == 0) revert PredictionMarket__EmptyDataSource();
        if (threshold == 0) revert PredictionMarket__InvalidThreshold();
        if (uint256(resolutionTime) <= block.timestamp + MIN_LEAD_TIME) revert PredictionMarket__ResolutionTimeInPast();
        if (ambiguityBandBps == 0 || ambiguityBandBps > AMBIGUITY_BAND_MAX_BPS) {
            revert PredictionMarket__InvalidAmbiguityBand();
        }
        if (address(this).balance < RESERVE_FLOOR) {
            revert PredictionMarket__InsufficientReactivityFunds(address(this).balance, RESERVE_FLOOR);
        }

        marketId = ++s_marketCount;
        s_markets[marketId] = Market({
            id: marketId,
            creator: msg.sender,
            question: question,
            dataSource: dataSource,
            jsonSelector: jsonSelector,
            threshold: threshold,
            ambiguityBandBps: ambiguityBandBps,
            resolutionTime: resolutionTime,
            yesPool: 0,
            noPool: 0,
            status: MarketStatus.Open,
            verdict: Verdict.Unset,
            subscriptionId: 0,
            pendingRequestId: 0,
            pendingAgentType: AgentRequestType.None,
            resolvedAt: 0
        });

        emit MarketCreated(marketId, msg.sender, question, resolutionTime);

        // [ARCHITECTURE-DECISION] The reactivity precompile returns subscriptionId, so reverse-lookup writes
        // happen after this external call. The precompile is fixed at address(0x0100), and the market is already
        // stored before scheduling, so a duplicate callback cannot corrupt terminal state.
        // slither-disable-next-line reentrancy-benign,reentrancy-events
        uint256 subscriptionId = SomniaExtensions.scheduleSubscriptionAtTimestamp(
            address(this), uint256(resolutionTime) * 1000, SomniaExtensions.defaultSubscriptionOptions()
        );
        s_markets[marketId].subscriptionId = subscriptionId;
        s_subscriptionToMarket[subscriptionId] = marketId;
        emit ResolutionScheduled(marketId, subscriptionId, resolutionTime);

        if (address(this).balance < LOW_BALANCE_THRESHOLD) {
            emit LowReactivityBalance(address(this).balance);
        }
    }

    /// @notice Commit STT to a YES or NO position on an Open market.
    /// @param marketId  The market to bet on.
    /// @param side      0 = YES, 1 = NO.
    /// @dev Reverts: MarketDoesNotExist | MarketNotOpen | MarketClosed | BetBelowMinimum | InvalidSide.
    ///      Uses nonReentrant guard. ETH stays in contract as pool collateral (AR-3).
    function placeBet(uint256 marketId, uint8 side) external payable nonReentrant {
        if (s_markets[marketId].id == 0) revert PredictionMarket__MarketDoesNotExist();
        if (s_markets[marketId].status != MarketStatus.Open) revert PredictionMarket__MarketNotOpen();
        if (block.timestamp >= uint256(s_markets[marketId].resolutionTime)) revert PredictionMarket__MarketClosed();
        if (msg.value < MIN_BET) revert PredictionMarket__BetBelowMinimum();
        if (side > 1) revert PredictionMarket__InvalidSide();

        if (side == 0) {
            s_markets[marketId].yesPool += msg.value;
        } else {
            s_markets[marketId].noPool += msg.value;
        }
        s_bets[marketId][msg.sender][side] += msg.value;

        emit BetPlaced(marketId, msg.sender, side, msg.value);
    }

    /// @notice Receive a result from the Somnia Agents platform and route to the correct handler.
    /// @param requestId  The agent request ID returned by createRequest.
    /// @param responses  Array of validator responses; decoded by handler stubs in 1.8/1.9.
    /// @param status     Consensus status from the platform — Success, Failed, or TimedOut.
    /// @param details    Original request details; opaque in this story.
    /// @dev Reverts if caller is not the Somnia Agents platform contract.
    ///      Clears pendingRequestId and pendingAgentType before dispatch to prevent double-callback.
    function handleResponse(
        uint256 requestId,
        ISomniaAgents.Response[] memory responses,
        ISomniaAgents.ResponseStatus status,
        ISomniaAgents.Request memory details
    ) external {
        if (msg.sender != i_somniaAgents) revert PredictionMarket__OnlySomniaAgents();
        details; // opaque in this story; never decoded — suppresses unused-parameter warning

        uint256 marketId = s_requestToMarket[requestId];
        if (marketId == 0) revert PredictionMarket__UnknownRequest();
        if (s_markets[marketId].pendingRequestId != requestId) revert PredictionMarket__UnknownRequest();

        AgentRequestType agentType = s_markets[marketId].pendingAgentType;
        s_markets[marketId].pendingRequestId = 0;
        s_markets[marketId].pendingAgentType = AgentRequestType.None;

        if (agentType == AgentRequestType.JsonApi) {
            _handleJsonResponse(marketId, requestId, responses, status);
        } else {
            _handleLlmResponse(marketId, requestId, responses, status);
        }
    }

    /// @notice Withdraw winnings from a resolved market.
    /// @param marketId The resolved market to claim from.
    /// @dev Reverts: InvalidStateTransition (not Resolved), AlreadyClaimed, NotWinningPosition (wrong/no side).
    ///      CEI enforced — s_claimed set before ETH transfer. nonReentrant for belt-and-suspenders defense.
    ///      ETH transfer via low-level .call; reverts TransferFailed on rejection (e.g. contract without receive).
    ///      Payout formula: (myWinningStake * losingPool) / winningPool + myWinningStake — see SettlementLib.
    function claim(uint256 marketId) external nonReentrant {
        Market storage market = s_markets[marketId];
        MarketLib.requireStatus(market.status, MarketStatus.Resolved);
        if (s_claimed[marketId][msg.sender]) revert PredictionMarket__AlreadyClaimed();

        uint8 winningSide;
        uint256 winningPool;
        uint256 losingPool;
        if (market.verdict == Verdict.YES) {
            winningSide = 0;
            winningPool = market.yesPool;
            losingPool = market.noPool;
        } else {
            winningSide = 1;
            winningPool = market.noPool;
            losingPool = market.yesPool;
        }

        uint256 myWinningStake = s_bets[marketId][msg.sender][winningSide];
        uint256 payout = SettlementLib.calculatePayout(myWinningStake, winningPool, losingPool);

        // CEI: state before transfer
        s_claimed[marketId][msg.sender] = true;

        // [ARCHITECTURE-DECISION] msg.sender is the legitimate claimant; s_claimed[marketId][msg.sender] is
        // set to true above (CEI). nonReentrant prevents reentrancy at the call stack level. Recipient is
        // always the caller, never an arbitrary third party.
        // slither-disable-next-line arbitrary-send-eth
        (bool ok,) = msg.sender.call{value: payout}("");
        if (!ok) revert PredictionMarket__TransferFailed();

        emit Claimed(marketId, msg.sender, payout);
    }

    /// @notice Recover full stake from an INVALID or Disputed market.
    /// @param marketId The INVALID/Disputed market to refund from.
    /// @dev Reverts: InvalidStateTransition (not Refunded/Disputed), AlreadyRefunded, NotRefundable (no bets).
    ///      [ARCHITECTURE-DECISION] Status check uses isRefundable (accepts both Refunded+INVALID and Disputed+Unset)
    ///      so requireStatus cannot be used (it checks a single expected value). The error uses Refunded as
    ///      the "expected" argument to convey "must be in a refundable state" — semantic imprecision is
    ///      justified by avoiding a new error solely for this case. Both end-states use the identical code path:
    ///      the verdict+status pair difference is preserved in storage for the frontend to distinguish (UX-DR9).
    ///      CEI enforced — s_refunded set before ETH transfer. nonReentrant guards value transfer.
    function refund(uint256 marketId) external nonReentrant {
        Market storage market = s_markets[marketId];
        if (!MarketLib.isRefundable(market.status, market.verdict)) {
            revert PredictionMarket__InvalidStateTransition(market.status, MarketStatus.Refunded);
        }
        if (s_refunded[marketId][msg.sender]) revert PredictionMarket__AlreadyRefunded();

        uint256 myYesStake = s_bets[marketId][msg.sender][0];
        uint256 myNoStake = s_bets[marketId][msg.sender][1];
        uint256 refundAmount = SettlementLib.calculateRefund(myYesStake, myNoStake);

        // CEI: state before transfer
        s_refunded[marketId][msg.sender] = true;

        // [ARCHITECTURE-DECISION] msg.sender is the legitimate refund recipient; s_refunded[marketId][msg.sender]
        // is set to true above (CEI). nonReentrant prevents reentrancy. Recipient is always the caller.
        // slither-disable-next-line arbitrary-send-eth
        (bool ok,) = msg.sender.call{value: refundAmount}("");
        if (!ok) revert PredictionMarket__TransferFailed();

        emit Refunded(marketId, msg.sender, refundAmount);
    }

    // ============ Internal Functions ============

    /// @notice Decode a JSON API agent result, compare to threshold ± Ambiguity Band, and route.
    /// @param marketId  The market being resolved (must be in Resolving state).
    /// @param requestId The original agent request ID, forwarded to _settleMarket for the MarketResolved event.
    /// @param responses Agent validator responses; responses[0].result is ABI-encoded uint256.
    /// @param status    Consensus status — Failed/TimedOut transitions to Disputed; Success proceeds to decode.
    /// @dev On agent failure: Resolving → Disputed, emits ResolutionFailed.
    ///      Clear YES/NO: calls _settleMarket → Resolved.
    ///      Ambiguous (in band): Resolving → LLMResolving; LLM invocation stubbed for Story 1.9.
    function _handleJsonResponse(
        uint256 marketId,
        uint256 requestId,
        ISomniaAgents.Response[] memory responses,
        ISomniaAgents.ResponseStatus status
    ) internal {
        MarketLib.requireStatus(s_markets[marketId].status, MarketStatus.Resolving);

        if (status != ISomniaAgents.ResponseStatus.Success) {
            s_markets[marketId].status = MarketStatus.Disputed;
            emit ResolutionFailed(marketId, uint8(status));
            return;
        }

        uint256 fetchedValue = abi.decode(responses[0].result, (uint256));

        uint256 threshold = s_markets[marketId].threshold;
        uint256 ambiguityBandBps = s_markets[marketId].ambiguityBandBps;
        uint256 bandLow = threshold - (threshold * ambiguityBandBps / BPS_DENOMINATOR);
        uint256 bandHigh = threshold + (threshold * ambiguityBandBps / BPS_DENOMINATOR);

        if (fetchedValue < bandLow) {
            _settleMarket(marketId, Verdict.NO, requestId);
        } else if (fetchedValue > bandHigh) {
            _settleMarket(marketId, Verdict.YES, requestId);
        } else {
            s_markets[marketId].status = MarketStatus.LLMResolving;
            _invokeLlm(marketId, fetchedValue);
        }
    }

    /// @notice Construct a constrained inferString prompt and invoke the LLM Tiebreaker agent (FR-8).
    /// @param marketId    The market in LLMResolving state.
    /// @param fetchedValue The JSON API value that landed in the ambiguity band, used in the prompt.
    /// @dev allowedValues=["YES","NO","INVALID"] + chainOfThought=true + INVALID system instruction
    ///      ensure the AI shows its work and can honestly signal inconclusive data (FR-8 philosophy).
    function _invokeLlm(uint256 marketId, uint256 fetchedValue) internal {
        Market storage market = s_markets[marketId];

        string[] memory allowedValues = new string[](3);
        allowedValues[0] = "YES";
        allowedValues[1] = "NO";
        allowedValues[2] = "INVALID";

        uint256 threshold = market.threshold;
        uint256 bandBps = market.ambiguityBandBps;
        uint256 bandLow = threshold - (threshold * bandBps / BPS_DENOMINATOR);
        uint256 bandHigh = threshold + (threshold * bandBps / BPS_DENOMINATOR);

        string memory prompt = string.concat(
            "Market question: ",
            market.question,
            "\n\nA data source returned the value ",
            Strings.toString(fetchedValue),
            ".\nThe market threshold is ",
            Strings.toString(threshold),
            ".\nThe ambiguity band spans ",
            Strings.toString(bandLow),
            " to ",
            Strings.toString(bandHigh),
            " (",
            Strings.toString(bandBps),
            " bps).\nThe fetched value falls within this band.\n\nRespond YES if the market condition is clearly met, NO if clearly not met, or INVALID if the evidence is genuinely ambiguous."
        );

        string memory system =
            "You are an objective market resolution oracle. INVALID is a first-class verdict that triggers a full refund to all bettors when the data is genuinely ambiguous or insufficient to decide clearly. Do not guess; choose INVALID when uncertain.";

        bytes memory payload =
            abi.encodeWithSignature("inferString(string,string,bool,string[])", prompt, system, true, allowedValues);

        // [ARCHITECTURE-DECISION] State writes (s_requestToMarket, pendingRequestId, pendingAgentType) occur
        // after the external call because the requestId is not known until createRequest returns. Re-entry is
        // safe: market is already in LLMResolving before _invokeLlm is called; any re-entrant handleResponse
        // would fail s_requestToMarket[newRequestId]==0 → UnknownRequest. i_somniaAgents is immutable/trusted.
        // Recipient is the immutable trusted Somnia Agents platform, never user-controlled.
        // slither-disable-next-line arbitrary-send-eth,reentrancy-eth,reentrancy-benign
        uint256 newRequestId = ISomniaAgents(i_somniaAgents).createRequest{value: LLM_DEPOSIT}(
            LLM_AGENT_ID, address(this), this.handleResponse.selector, payload
        );

        s_requestToMarket[newRequestId] = marketId;
        market.pendingRequestId = newRequestId;
        market.pendingAgentType = AgentRequestType.Llm;
    }

    /// @notice Decode the LLM Tiebreaker verdict and finalize the market (FR-8, FR-9 complete).
    /// @param marketId  The market being resolved (must be in LLMResolving state).
    /// @param requestId The original LLM agent request ID forwarded to _settleMarket / MarketResolved.
    /// @param responses Agent validator responses; responses[0].result is ABI-encoded string.
    /// @param status    Consensus status — Failed/TimedOut transitions to Disputed; Success proceeds to decode.
    /// @dev Verdict matching is case-sensitive via keccak256(bytes(...)) — allowedValues constraint ensures
    ///      the LLM cannot produce an unexpected casing variant in normal operation.
    ///      Unknown string (should not occur) → Disputed so bettors can refund (NFR-5: no admin recovery path).
    ///      [ARCHITECTURE-DECISION] Unknown verdict falls to Disputed rather than hanging: Somi has no admin
    ///      (NFR-5) so manual recovery is impossible; Disputed exposes refund() to all bettors via FR-11.
    function _handleLlmResponse(
        uint256 marketId,
        uint256 requestId,
        ISomniaAgents.Response[] memory responses,
        ISomniaAgents.ResponseStatus status
    ) internal {
        MarketLib.requireStatus(s_markets[marketId].status, MarketStatus.LLMResolving);

        if (status != ISomniaAgents.ResponseStatus.Success) {
            s_markets[marketId].status = MarketStatus.Disputed;
            emit ResolutionFailed(marketId, uint8(status));
            return;
        }

        string memory verdict = abi.decode(responses[0].result, (string));

        if (keccak256(bytes(verdict)) == keccak256(bytes("YES"))) {
            _settleMarket(marketId, Verdict.YES, requestId);
        } else if (keccak256(bytes(verdict)) == keccak256(bytes("NO"))) {
            _settleMarket(marketId, Verdict.NO, requestId);
        } else if (keccak256(bytes(verdict)) == keccak256(bytes("INVALID"))) {
            s_markets[marketId].status = MarketStatus.Refunded;
            s_markets[marketId].verdict = Verdict.INVALID;
            s_markets[marketId].resolvedAt = uint64(block.timestamp);
            emit MarketResolved(marketId, Verdict.INVALID, 0, 0, requestId);
        } else {
            // [ARCHITECTURE-DECISION] Unknown verdict despite allowedValues constraint.
            // Somi has no admin (NFR-5) so manual recovery is impossible; Disputed lets bettors refund via FR-11.
            s_markets[marketId].status = MarketStatus.Disputed;
            emit ResolutionFailed(marketId, uint8(ISomniaAgents.ResponseStatus.Success));
        }
    }

    /// @notice Record verdict, mark market Resolved, and emit MarketResolved (FR-9).
    /// @param marketId  The market to settle.
    /// @param verdict   YES or NO — INVALID verdict is written directly by _handleLlmResponse (Story 1.9).
    /// @param requestId Original agent request ID emitted in MarketResolved for off-chain receipt URL construction (AR-7, Decision 5).
    /// @dev Called from _handleJsonResponse (Resolving → Resolved) and from _handleLlmResponse (Story 1.9, LLMResolving → Resolved).
    ///      Callers validate the prior status before invoking; no requireStatus guard here.
    ///      Settlement occurs in the same block as the triggering reactivity event (NFR-2, same-block guarantee).
    function _settleMarket(uint256 marketId, Verdict verdict, uint256 requestId) internal {
        s_markets[marketId].status = MarketStatus.Resolved;
        s_markets[marketId].verdict = verdict;
        s_markets[marketId].resolvedAt = uint64(block.timestamp);

        uint256 winningPool;
        uint256 losingPool;
        if (verdict == Verdict.YES) {
            winningPool = s_markets[marketId].yesPool;
            losingPool = s_markets[marketId].noPool;
        } else {
            winningPool = s_markets[marketId].noPool;
            losingPool = s_markets[marketId].yesPool;
        }

        emit MarketResolved(marketId, verdict, winningPool, losingPool, requestId);
        _publishOutcome(marketId, requestId); // [Epic 5]
    }

    /// @notice Publish settled market outcome to Somnia Data Streams (FR-12, best-effort).
    /// @dev Wrapped in try/catch — Streams failure never reverts settlement. Called as the final
    ///      action of _settleMarket, after MarketResolved is emitted, so settlement state is durable
    ///      regardless of Streams success. INVALID markets (via _handleLlmResponse) do not call this.
    /// @param marketId  The settled market.
    /// @param requestId The agent request ID, included in the Streams payload for cross-referencing.
    function _publishOutcome(uint256 marketId, uint256 requestId) internal {
        Market storage market = s_markets[marketId];
        ISomniaStreams.DataStream[] memory streams = new ISomniaStreams.DataStream[](1);
        streams[0] = ISomniaStreams.DataStream({
            id: bytes32(marketId),
            schemaId: STREAMS_SCHEMA_ID,
            data: abi.encode(marketId, market.question, uint8(market.verdict), market.resolvedAt, requestId)
        });
        try ISomniaStreams(STREAMS_PROXY).esstores(streams) {}
        catch Error(string memory reason) {
            emit StreamsPublishFailed(marketId, reason);
        } catch {
            emit StreamsPublishFailed(marketId, "");
        }
    }

    /// @notice Autonomous resolution trigger — fires in the same block as `resolutionTime` (NFR-2 same-block guarantee).
    /// @dev Somnia precompile packs `abi.encode(subscriptionId)` into `data` for scheduled callbacks.
    ///      Reverse-lookup: s_subscriptionToMarket[subscriptionId] → marketId.
    ///      Graceful-fail path: if balance < JSON_DEPOSIT, emits ResolutionDeferred and returns with NO
    ///      state mutation — the market stays Open and will never auto-resolve (NFR-5 no-admin caveat).
    ///      Status guard (requireStatus Open) prevents a duplicate callback from corrupting a market
    ///      already in Resolving/LLMResolving state (should not occur with one-shot subscriptions).
    function _onEvent(address, bytes32[] calldata, bytes calldata data) internal override {
        uint256 subscriptionId = abi.decode(data, (uint256));
        uint256 marketId = s_subscriptionToMarket[subscriptionId];

        if (address(this).balance < JSON_DEPOSIT) {
            emit ResolutionDeferred(marketId);
            return;
        }

        Market storage market = s_markets[marketId];
        MarketLib.requireStatus(market.status, MarketStatus.Open);
        market.status = MarketStatus.Resolving;

        bytes memory payload =
            abi.encodeWithSignature("fetchUint(string,string,uint8)", market.dataSource, market.jsonSelector, uint8(0));

        // [ARCHITECTURE-DECISION] State writes (s_requestToMarket, pendingRequestId, pendingAgentType) occur
        // after the external call because requestId is not known until createRequest returns. Re-entry is safe:
        // market is already Resolving; any re-entrant handleResponse fails UnknownRequest since the new requestId
        // isn't in s_requestToMarket yet. i_somniaAgents is immutable/trusted.
        // Recipient is the immutable trusted Somnia Agents platform, never user-controlled.
        // slither-disable-next-line arbitrary-send-eth,reentrancy-eth,reentrancy-benign,reentrancy-events
        uint256 requestId = ISomniaAgents(i_somniaAgents).createRequest{value: JSON_DEPOSIT}(
            JSON_AGENT_ID, address(this), this.handleResponse.selector, payload
        );

        s_requestToMarket[requestId] = marketId;
        market.pendingRequestId = requestId;
        market.pendingAgentType = AgentRequestType.JsonApi;

        emit ResolutionInitiated(marketId, requestId);
    }

    // ============ View Functions ============

    /// @notice Returns the full Market struct for a given marketId.
    /// @param marketId The market to query.
    function getMarket(uint256 marketId) external view returns (Market memory) {
        return s_markets[marketId];
    }

    /// @notice Returns the total number of markets created.
    function getMarketCount() external view returns (uint256) {
        return s_marketCount;
    }

    /// @notice Returns a bettor's staked amount on a specific side of a market.
    /// @param marketId  The market to query.
    /// @param bettor    Address of the bettor.
    /// @param side      0 = YES, 1 = NO.
    function getBet(uint256 marketId, address bettor, uint8 side) external view returns (uint256) {
        return s_bets[marketId][bettor][side];
    }
}
