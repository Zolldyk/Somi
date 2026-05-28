// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

// ============ Imports ============
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SomniaEventHandler} from "@somnia-chain/reactivity-contracts/contracts/SomniaEventHandler.sol";
import {MarketLib, MarketStatus, Verdict, AgentRequestType} from "./libraries/MarketLib.sol";
import {
    SettlementLib,
    PredictionMarket__NotWinningPosition,
    PredictionMarket__NotRefundable
} from "./libraries/SettlementLib.sol";

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

    address private immutable i_somniaAgents;

    mapping(uint256 => Market) private s_markets;
    mapping(uint256 => mapping(address => mapping(uint8 => uint256))) private s_bets;
    mapping(uint256 => mapping(address => bool)) private s_claimed;
    mapping(uint256 => mapping(address => bool)) private s_refunded;
    mapping(uint256 => uint256) private s_requestToMarket;
    uint256 private s_marketCount;

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

        // TODO(Story 1.11): scheduleSubscriptionAtTimestamp

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

    // ============ Internal Functions ============

    /// @inheritdoc SomniaEventHandler
    function _onEvent(address, bytes32[] calldata, bytes calldata) internal override {
        // TODO(Story 1.11): implement reactivity callback
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
