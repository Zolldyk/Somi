// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, Vm} from "forge-std/Test.sol";
import {PredictionMarket} from "../src/PredictionMarket.sol";
import {MarketStatus, Verdict, AgentRequestType} from "../src/libraries/MarketLib.sol";
import {ISomniaAgents} from "../src/interfaces/ISomniaAgents.sol";
import {MockSomniaAgents} from "./mocks/MockSomniaAgents.sol";

contract PredictionMarketTest is Test {
    PredictionMarket private s_pm;
    MockSomniaAgents private s_mockAgents;
    address private constant MOCK_AGENTS = address(0xA9E5);

    uint256 private constant RESERVE_FLOOR = 32 ether;
    uint256 private constant LOW_BALANCE_THRESHOLD = 35 ether;
    uint256 private constant MIN_LEAD_TIME = 5 minutes;
    uint256 private constant AMBIGUITY_BAND_MAX_BPS = 1000;

    string private constant QUESTION = "Will BTC close above $110,000 on June 5?";
    string private constant DATA_SOURCE = "https://api.coingecko.com/api/v3/simple/price?ids=bitcoin&vs_currencies=usd";
    string private constant JSON_SELECTOR = "bitcoin.usd";
    uint256 private constant THRESHOLD = 110_000;
    uint256 private constant BAND_BPS = 100;
    uint256 private constant MIN_BET = 0.01 ether;
    uint256 private constant BET_AMOUNT = 5 ether;

    function setUp() public {
        // Step 1: deploy mock with placeholder to break the chicken-and-egg dependency
        s_mockAgents = new MockSomniaAgents(address(0));
        // Step 2: deploy PM with mock's address as the agents contract
        s_pm = new PredictionMarket{value: 50 ether}(address(s_mockAgents));
        // Step 3: wire the mock back to PM
        s_mockAgents.setTarget(address(s_pm));
    }

    // ============ Happy Path ============

    function test_CreateMarket_HappyPath() public {
        uint64 resolutionTime = uint64(block.timestamp + MIN_LEAD_TIME + 1);

        vm.expectEmit(true, true, false, true, address(s_pm));
        emit PredictionMarket.MarketCreated(1, address(this), QUESTION, resolutionTime);

        uint256 marketId = s_pm.createMarket(QUESTION, DATA_SOURCE, JSON_SELECTOR, THRESHOLD, resolutionTime, BAND_BPS);

        assertEq(marketId, 1);

        PredictionMarket.Market memory m = s_pm.getMarket(marketId);
        assertEq(m.id, 1);
        assertEq(m.creator, address(this));
        assertEq(m.question, QUESTION);
        assertEq(m.dataSource, DATA_SOURCE);
        assertEq(m.jsonSelector, JSON_SELECTOR);
        assertEq(m.threshold, THRESHOLD);
        assertEq(m.ambiguityBandBps, BAND_BPS);
        assertEq(m.resolutionTime, resolutionTime);
        assertEq(m.yesPool, 0);
        assertEq(m.noPool, 0);
        assertEq(uint8(m.status), uint8(MarketStatus.Open));
        assertEq(uint8(m.verdict), uint8(Verdict.Unset));
        assertEq(uint8(m.pendingAgentType), uint8(AgentRequestType.None));
        assertEq(m.subscriptionId, 0);
        assertEq(m.pendingRequestId, 0);
        assertEq(m.resolvedAt, 0);
    }

    function test_CreateMarket_MonotonicIds() public {
        uint64 resolutionTime = uint64(block.timestamp + MIN_LEAD_TIME + 1);

        uint256 id1 = s_pm.createMarket(QUESTION, DATA_SOURCE, JSON_SELECTOR, THRESHOLD, resolutionTime, BAND_BPS);
        uint256 id2 = s_pm.createMarket(QUESTION, DATA_SOURCE, JSON_SELECTOR, THRESHOLD, resolutionTime, BAND_BPS);
        uint256 id3 = s_pm.createMarket(QUESTION, DATA_SOURCE, JSON_SELECTOR, THRESHOLD, resolutionTime, BAND_BPS);

        assertEq(id1, 1);
        assertEq(id2, 2);
        assertEq(id3, 3);
    }

    // ============ Input Validation Reverts ============

    function test_CreateMarket_RevertsOnEmptyQuestion() public {
        uint64 resolutionTime = uint64(block.timestamp + MIN_LEAD_TIME + 1);
        vm.expectRevert(PredictionMarket.PredictionMarket__EmptyQuestion.selector);
        s_pm.createMarket("", DATA_SOURCE, JSON_SELECTOR, THRESHOLD, resolutionTime, BAND_BPS);
    }

    function test_CreateMarket_RevertsOnEmptyDataSource() public {
        uint64 resolutionTime = uint64(block.timestamp + MIN_LEAD_TIME + 1);
        vm.expectRevert(PredictionMarket.PredictionMarket__EmptyDataSource.selector);
        s_pm.createMarket(QUESTION, "", JSON_SELECTOR, THRESHOLD, resolutionTime, BAND_BPS);
    }

    function test_CreateMarket_RevertsOnZeroThreshold() public {
        uint64 resolutionTime = uint64(block.timestamp + MIN_LEAD_TIME + 1);
        vm.expectRevert(PredictionMarket.PredictionMarket__InvalidThreshold.selector);
        s_pm.createMarket(QUESTION, DATA_SOURCE, JSON_SELECTOR, 0, resolutionTime, BAND_BPS);
    }

    function test_CreateMarket_RevertsOnResolutionTimeInPast() public {
        // At exactly block.timestamp + MIN_LEAD_TIME — boundary must revert
        uint64 resolutionTime = uint64(block.timestamp + MIN_LEAD_TIME);
        vm.expectRevert(PredictionMarket.PredictionMarket__ResolutionTimeInPast.selector);
        s_pm.createMarket(QUESTION, DATA_SOURCE, JSON_SELECTOR, THRESHOLD, resolutionTime, BAND_BPS);
    }

    function test_CreateMarket_RevertsOnZeroAmbiguityBand() public {
        uint64 resolutionTime = uint64(block.timestamp + MIN_LEAD_TIME + 1);
        vm.expectRevert(PredictionMarket.PredictionMarket__InvalidAmbiguityBand.selector);
        s_pm.createMarket(QUESTION, DATA_SOURCE, JSON_SELECTOR, THRESHOLD, resolutionTime, 0);
    }

    function test_CreateMarket_RevertsOnAmbiguityBandExceedsMax() public {
        uint64 resolutionTime = uint64(block.timestamp + MIN_LEAD_TIME + 1);
        vm.expectRevert(PredictionMarket.PredictionMarket__InvalidAmbiguityBand.selector);
        s_pm.createMarket(QUESTION, DATA_SOURCE, JSON_SELECTOR, THRESHOLD, resolutionTime, 1001);
    }

    // ============ Balance Guards ============

    function test_CreateMarket_RevertsOnInsufficientBalance() public {
        uint64 resolutionTime = uint64(block.timestamp + MIN_LEAD_TIME + 1);

        // Drain balance below RESERVE_FLOOR
        vm.deal(address(s_pm), 31 ether);

        vm.expectRevert(
            abi.encodeWithSelector(
                PredictionMarket.PredictionMarket__InsufficientReactivityFunds.selector, 31 ether, RESERVE_FLOOR
            )
        );
        s_pm.createMarket(QUESTION, DATA_SOURCE, JSON_SELECTOR, THRESHOLD, resolutionTime, BAND_BPS);
    }

    function test_CreateMarket_EmitsLowReactivityBalance() public {
        uint64 resolutionTime = uint64(block.timestamp + MIN_LEAD_TIME + 1);

        // Set balance above RESERVE_FLOOR but below LOW_BALANCE_THRESHOLD
        vm.deal(address(s_pm), 33 ether);

        vm.expectEmit(false, false, false, true, address(s_pm));
        emit PredictionMarket.LowReactivityBalance(33 ether);

        s_pm.createMarket(QUESTION, DATA_SOURCE, JSON_SELECTOR, THRESHOLD, resolutionTime, BAND_BPS);
    }

    function test_CreateMarket_NoLowBalanceEventAboveThreshold() public {
        uint64 resolutionTime = uint64(block.timestamp + MIN_LEAD_TIME + 1);

        // 36 ether — above LOW_BALANCE_THRESHOLD (35 ether)
        vm.deal(address(s_pm), 36 ether);

        // Record logs to verify LowReactivityBalance is NOT emitted
        vm.recordLogs();
        s_pm.createMarket(QUESTION, DATA_SOURCE, JSON_SELECTOR, THRESHOLD, resolutionTime, BAND_BPS);

        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 lowBalanceSig = keccak256("LowReactivityBalance(uint256)");
        for (uint256 i; i < entries.length; i++) {
            assertTrue(entries[i].topics[0] != lowBalanceSig, "LowReactivityBalance must not fire above threshold");
        }
    }

    // ============ placeBet Helpers ============

    function _createDefaultMarket() internal returns (uint256 marketId, uint64 resolutionTime) {
        resolutionTime = uint64(block.timestamp + MIN_LEAD_TIME + 1);
        marketId = s_pm.createMarket(QUESTION, DATA_SOURCE, JSON_SELECTOR, THRESHOLD, resolutionTime, BAND_BPS);
    }

    // ============ placeBet — Happy Paths ============

    function test_PlaceBet_YesSide() public {
        (uint256 id,) = _createDefaultMarket();

        vm.expectEmit(true, true, true, true, address(s_pm));
        emit PredictionMarket.BetPlaced(id, address(this), 0, BET_AMOUNT);

        s_pm.placeBet{value: BET_AMOUNT}(id, 0);

        PredictionMarket.Market memory m = s_pm.getMarket(id);
        assertEq(m.yesPool, BET_AMOUNT);
        assertEq(m.noPool, 0);
        assertEq(s_pm.getBet(id, address(this), 0), BET_AMOUNT);
    }

    function test_PlaceBet_NoSide() public {
        (uint256 id,) = _createDefaultMarket();

        vm.expectEmit(true, true, true, true, address(s_pm));
        emit PredictionMarket.BetPlaced(id, address(this), 1, BET_AMOUNT);

        s_pm.placeBet{value: BET_AMOUNT}(id, 1);

        PredictionMarket.Market memory m = s_pm.getMarket(id);
        assertEq(m.noPool, BET_AMOUNT);
        assertEq(m.yesPool, 0);
        assertEq(s_pm.getBet(id, address(this), 1), BET_AMOUNT);
    }

    function test_PlaceBet_MultiBetAccumulation() public {
        (uint256 id,) = _createDefaultMarket();

        s_pm.placeBet{value: 3 ether}(id, 0);
        s_pm.placeBet{value: 2 ether}(id, 0);

        PredictionMarket.Market memory m = s_pm.getMarket(id);
        assertEq(m.yesPool, 5 ether);
        assertEq(s_pm.getBet(id, address(this), 0), 5 ether);
    }

    function test_PlaceBet_BothSidesBySameUser() public {
        (uint256 id,) = _createDefaultMarket();

        s_pm.placeBet{value: 3 ether}(id, 0);
        s_pm.placeBet{value: 2 ether}(id, 1);

        PredictionMarket.Market memory m = s_pm.getMarket(id);
        assertEq(m.yesPool, 3 ether);
        assertEq(m.noPool, 2 ether);
        assertEq(s_pm.getBet(id, address(this), 0), 3 ether);
        assertEq(s_pm.getBet(id, address(this), 1), 2 ether);
    }

    // ============ placeBet — Revert Conditions ============

    function test_PlaceBet_RevertsOnMarketDoesNotExist() public {
        vm.expectRevert(PredictionMarket.PredictionMarket__MarketDoesNotExist.selector);
        s_pm.placeBet{value: BET_AMOUNT}(99, 0);
    }

    function test_PlaceBet_RevertsOnMarketNotOpen() public {
        (uint256 id,) = _createDefaultMarket();

        bytes32 marketBase = keccak256(abi.encode(id, uint256(0)));
        bytes32 statusSlot = bytes32(uint256(marketBase) + 10);
        vm.store(address(s_pm), statusSlot, bytes32(uint256(1)));

        vm.expectRevert(PredictionMarket.PredictionMarket__MarketNotOpen.selector);
        s_pm.placeBet{value: BET_AMOUNT}(id, 0);
    }

    function test_PlaceBet_RevertsOnMarketClosed() public {
        (uint256 id, uint64 resolutionTime) = _createDefaultMarket();

        vm.warp(resolutionTime);

        vm.expectRevert(PredictionMarket.PredictionMarket__MarketClosed.selector);
        s_pm.placeBet{value: BET_AMOUNT}(id, 0);
    }

    function test_PlaceBet_RevertsOnBetBelowMinimum() public {
        (uint256 id,) = _createDefaultMarket();

        vm.expectRevert(PredictionMarket.PredictionMarket__BetBelowMinimum.selector);
        s_pm.placeBet{value: MIN_BET - 1}(id, 0);
    }

    function test_PlaceBet_RevertsOnInvalidSide() public {
        (uint256 id,) = _createDefaultMarket();

        vm.expectRevert(PredictionMarket.PredictionMarket__InvalidSide.selector);
        s_pm.placeBet{value: BET_AMOUNT}(id, 2);
    }

    // ============ Fuzz Tests ============

    function testFuzz_CreateMarket_AcceptsAllValidInputs(uint256 threshold, uint256 futureOffset, uint256 bandBps)
        public
    {
        threshold = bound(threshold, 1, 1e27);
        futureOffset = bound(futureOffset, MIN_LEAD_TIME + 1, 365 days);
        bandBps = bound(bandBps, 1, AMBIGUITY_BAND_MAX_BPS);

        uint64 resolutionTime = uint64(block.timestamp + futureOffset);

        uint256 marketId = s_pm.createMarket(QUESTION, DATA_SOURCE, JSON_SELECTOR, threshold, resolutionTime, bandBps);

        assertTrue(marketId > 0);
        PredictionMarket.Market memory m = s_pm.getMarket(marketId);
        assertEq(m.threshold, threshold);
        assertEq(m.ambiguityBandBps, bandBps);
        assertEq(uint8(m.status), uint8(MarketStatus.Open));
    }

    function testFuzz_PlaceBet_AddsToPool(uint256 amount, bool isYes) public {
        amount = bound(amount, MIN_BET, 100 ether);
        (uint256 id,) = _createDefaultMarket();

        vm.deal(address(this), amount);
        uint8 side = isYes ? 0 : 1;

        s_pm.placeBet{value: amount}(id, side);

        PredictionMarket.Market memory m = s_pm.getMarket(id);
        if (isYes) {
            assertEq(m.yesPool, amount);
            assertEq(m.noPool, 0);
        } else {
            assertEq(m.noPool, amount);
            assertEq(m.yesPool, 0);
        }
        assertEq(s_pm.getBet(id, address(this), side), amount);
    }

    // ============ handleResponse Helpers ============

    /// @dev Seeds s_requestToMarket[requestId] = marketId and sets market's pending fields via vm.store.
    ///      Slot layout (non-constant, non-immutable state vars in order):
    ///        slot 0: s_markets, slot 1: s_bets, slot 2: s_claimed, slot 3: s_refunded,
    ///        slot 4: s_requestToMarket, slot 5: s_marketCount
    ///      Market struct field offsets (dynamic strings count as 1 slot each):
    ///        +0 id, +1 creator, +2 question, +3 dataSource, +4 jsonSelector,
    ///        +5 threshold, +6 ambiguityBandBps, +7 resolutionTime, +8 yesPool, +9 noPool,
    ///        +10 status+verdict (packed), +11 subscriptionId, +12 pendingRequestId,
    ///        +13 pendingAgentType+resolvedAt (packed)
    function _seedPendingRequest(uint256 marketId, uint256 requestId, AgentRequestType agentType) internal {
        bytes32 rtmSlot = keccak256(abi.encode(requestId, uint256(4)));
        vm.store(address(s_pm), rtmSlot, bytes32(marketId));

        bytes32 marketBase = keccak256(abi.encode(marketId, uint256(0)));
        vm.store(address(s_pm), bytes32(uint256(marketBase) + 12), bytes32(requestId));
        vm.store(address(s_pm), bytes32(uint256(marketBase) + 13), bytes32(uint256(agentType)));
    }

    // ============ handleResponse Tests ============

    /// @dev Creates a market in Resolving state with a seeded pending JSON request.
    ///      Combines _createDefaultMarket + _seedPendingRequest + status override.
    function _seedResolvingMarket(uint256 requestId) internal returns (uint256 marketId) {
        (marketId,) = _createDefaultMarket();
        _seedPendingRequest(marketId, requestId, AgentRequestType.JsonApi);
        // Set status to Resolving (=1) at struct offset +10
        bytes32 marketBase = keccak256(abi.encode(marketId, uint256(0)));
        bytes32 statusSlot = bytes32(uint256(marketBase) + 10);
        vm.store(address(s_pm), statusSlot, bytes32(uint256(1)));
    }

    /// @dev Creates a market in LLMResolving state with a seeded pending Llm request.
    ///      Parallel to _seedResolvingMarket but uses status=LLMResolving (=2) and AgentType=Llm.
    function _seedLLMResolvingMarket(uint256 requestId) internal returns (uint256 marketId) {
        (marketId,) = _createDefaultMarket();
        _seedPendingRequest(marketId, requestId, AgentRequestType.Llm);
        bytes32 marketBase = keccak256(abi.encode(marketId, uint256(0)));
        bytes32 statusSlot = bytes32(uint256(marketBase) + 10);
        vm.store(address(s_pm), statusSlot, bytes32(uint256(2))); // LLMResolving=2
    }

    // ============ handleResponse Tests ============

    function test_HandleResponse_RevertsWhenNotSomniaAgents() public {
        (uint256 id,) = _createDefaultMarket();
        _seedPendingRequest(id, 1, AgentRequestType.JsonApi);

        ISomniaAgents.Response[] memory responses = new ISomniaAgents.Response[](0);
        ISomniaAgents.Request memory req = ISomniaAgents.Request({payload: ""});

        vm.prank(address(0xBEEF));
        vm.expectRevert(PredictionMarket.PredictionMarket__OnlySomniaAgents.selector);
        s_pm.handleResponse(1, responses, ISomniaAgents.ResponseStatus.Success, req);
    }

    function test_HandleResponse_RevertsOnUnknownRequest() public {
        ISomniaAgents.Response[] memory responses = new ISomniaAgents.Response[](0);
        ISomniaAgents.Request memory req = ISomniaAgents.Request({payload: ""});

        vm.expectRevert(PredictionMarket.PredictionMarket__UnknownRequest.selector);
        s_mockAgents.callHandleResponse(99, responses, ISomniaAgents.ResponseStatus.Success, req);
    }

    function test_HandleResponse_ClearsPendingFieldsBeforeDispatch() public {
        (uint256 id,) = _createDefaultMarket();
        uint256 requestId = 42;
        _seedPendingRequest(id, requestId, AgentRequestType.JsonApi);

        // Story 1.8: set market to Resolving so requireStatus guard passes
        bytes32 marketBase = keccak256(abi.encode(id, uint256(0)));
        bytes32 statusSlot = bytes32(uint256(marketBase) + 10);
        vm.store(address(s_pm), statusSlot, bytes32(uint256(1))); // Resolving=1

        PredictionMarket.Market memory mBefore = s_pm.getMarket(id);
        assertEq(mBefore.pendingRequestId, requestId);
        assertEq(uint8(mBefore.pendingAgentType), uint8(AgentRequestType.JsonApi));

        // Use Failed status to avoid responses[0] array-bounds panic
        ISomniaAgents.Response[] memory responses = new ISomniaAgents.Response[](0);
        ISomniaAgents.Request memory req = ISomniaAgents.Request({payload: ""});
        s_mockAgents.callHandleResponse(requestId, responses, ISomniaAgents.ResponseStatus.Failed, req);

        PredictionMarket.Market memory mAfter = s_pm.getMarket(id);
        assertEq(mAfter.pendingRequestId, 0);
        assertEq(uint8(mAfter.pendingAgentType), uint8(AgentRequestType.None));
    }

    function test_HandleResponse_RevertsOnStaleRequestAfterLlmInvocation() public {
        uint256 oldJsonRequestId = 43;
        uint256 marketId = _seedResolvingMarket(oldJsonRequestId);

        ISomniaAgents.Response[] memory responses = new ISomniaAgents.Response[](1);
        responses[0] = ISomniaAgents.Response({result: abi.encode(THRESHOLD)});
        ISomniaAgents.Request memory req = ISomniaAgents.Request({payload: ""});

        s_mockAgents.callHandleResponse(oldJsonRequestId, responses, ISomniaAgents.ResponseStatus.Success, req);

        PredictionMarket.Market memory mAfterLlmInvoke = s_pm.getMarket(marketId);
        assertEq(uint8(mAfterLlmInvoke.status), uint8(MarketStatus.LLMResolving));
        assertEq(uint8(mAfterLlmInvoke.pendingAgentType), uint8(AgentRequestType.Llm));
        assertTrue(mAfterLlmInvoke.pendingRequestId != oldJsonRequestId);

        vm.expectRevert(PredictionMarket.PredictionMarket__UnknownRequest.selector);
        s_mockAgents.callHandleResponse(oldJsonRequestId, responses, ISomniaAgents.ResponseStatus.Success, req);
    }

    // ============ _handleJsonResponse Tests ============

    function test_HandleJsonResponse_DecodesValueAndSettlesYes() public {
        uint256 requestId = 10;
        uint256 marketId = _seedResolvingMarket(requestId);

        // fetchedValue = 120_000 → above bandHigh (111_100) → YES
        uint256 fetchedValue = 120_000;
        ISomniaAgents.Response[] memory responses = new ISomniaAgents.Response[](1);
        responses[0] = ISomniaAgents.Response({result: abi.encode(fetchedValue)});
        ISomniaAgents.Request memory req = ISomniaAgents.Request({payload: ""});

        vm.expectEmit(true, false, false, true, address(s_pm));
        emit PredictionMarket.MarketResolved(marketId, Verdict.YES, 0, 0, requestId);

        s_mockAgents.callHandleResponse(requestId, responses, ISomniaAgents.ResponseStatus.Success, req);

        PredictionMarket.Market memory m = s_pm.getMarket(marketId);
        assertEq(uint8(m.status), uint8(MarketStatus.Resolved));
        assertEq(uint8(m.verdict), uint8(Verdict.YES));
        assertTrue(m.resolvedAt > 0);
    }

    function test_HandleJsonResponse_SettlesNo() public {
        uint256 requestId = 11;
        uint256 marketId = _seedResolvingMarket(requestId);

        // fetchedValue = 100_000 → below bandLow (108_900) → NO
        uint256 fetchedValue = 100_000;
        ISomniaAgents.Response[] memory responses = new ISomniaAgents.Response[](1);
        responses[0] = ISomniaAgents.Response({result: abi.encode(fetchedValue)});
        ISomniaAgents.Request memory req = ISomniaAgents.Request({payload: ""});

        vm.expectEmit(true, false, false, true, address(s_pm));
        emit PredictionMarket.MarketResolved(marketId, Verdict.NO, 0, 0, requestId);

        s_mockAgents.callHandleResponse(requestId, responses, ISomniaAgents.ResponseStatus.Success, req);

        PredictionMarket.Market memory m = s_pm.getMarket(marketId);
        assertEq(uint8(m.status), uint8(MarketStatus.Resolved));
        assertEq(uint8(m.verdict), uint8(Verdict.NO));
        assertTrue(m.resolvedAt > 0);
    }

    function test_HandleJsonResponse_RoutesToLLMOnAmbiguity() public {
        uint256 requestId = 12;
        uint256 marketId = _seedResolvingMarket(requestId);

        // fetchedValue = 110_000 = THRESHOLD (exactly on threshold, inside band) → LLMResolving
        uint256 fetchedValue = THRESHOLD;
        ISomniaAgents.Response[] memory responses = new ISomniaAgents.Response[](1);
        responses[0] = ISomniaAgents.Response({result: abi.encode(fetchedValue)});
        ISomniaAgents.Request memory req = ISomniaAgents.Request({payload: ""});

        s_mockAgents.callHandleResponse(requestId, responses, ISomniaAgents.ResponseStatus.Success, req);

        PredictionMarket.Market memory m = s_pm.getMarket(marketId);
        assertEq(uint8(m.status), uint8(MarketStatus.LLMResolving));
        assertEq(uint8(m.verdict), uint8(Verdict.Unset));
        // Story 1.9: _invokeLlm fired → mock's createRequest returned 1 → pending fields updated
        assertEq(uint8(m.pendingAgentType), uint8(AgentRequestType.Llm));
        assertTrue(m.pendingRequestId != 0, "LLM request ID must be non-zero after _invokeLlm");
    }

    function test_HandleJsonResponse_MarksDisputedOnAgentFailure() public {
        uint256 requestId = 13;
        uint256 marketId = _seedResolvingMarket(requestId);

        ISomniaAgents.Response[] memory responses = new ISomniaAgents.Response[](0);
        ISomniaAgents.Request memory req = ISomniaAgents.Request({payload: ""});

        vm.expectEmit(true, false, false, true, address(s_pm));
        emit PredictionMarket.ResolutionFailed(marketId, uint8(ISomniaAgents.ResponseStatus.Failed));

        s_mockAgents.callHandleResponse(requestId, responses, ISomniaAgents.ResponseStatus.Failed, req);

        PredictionMarket.Market memory m = s_pm.getMarket(marketId);
        assertEq(uint8(m.status), uint8(MarketStatus.Disputed));
        assertEq(uint8(m.verdict), uint8(Verdict.Unset));
    }

    function test_HandleJsonResponse_MarksDisputedOnTimedOut() public {
        uint256 requestId = 14;
        uint256 marketId = _seedResolvingMarket(requestId);

        ISomniaAgents.Response[] memory responses = new ISomniaAgents.Response[](0);
        ISomniaAgents.Request memory req = ISomniaAgents.Request({payload: ""});

        vm.expectEmit(true, false, false, true, address(s_pm));
        emit PredictionMarket.ResolutionFailed(marketId, uint8(ISomniaAgents.ResponseStatus.TimedOut));

        s_mockAgents.callHandleResponse(requestId, responses, ISomniaAgents.ResponseStatus.TimedOut, req);

        PredictionMarket.Market memory m = s_pm.getMarket(marketId);
        assertEq(uint8(m.status), uint8(MarketStatus.Disputed));
    }

    function testFuzz_HandleJsonResponse_BandBoundaries(uint256 threshold, uint256 bandBps, uint256 fetchedValue)
        public
    {
        threshold = bound(threshold, 1, 1e27);
        bandBps = bound(bandBps, 1, 1000);

        uint64 resolutionTime = uint64(block.timestamp + MIN_LEAD_TIME + 1);
        uint256 marketId = s_pm.createMarket(QUESTION, DATA_SOURCE, JSON_SELECTOR, threshold, resolutionTime, bandBps);

        // Use marketId as requestId so each fuzz run has a unique, non-colliding requestId
        uint256 requestId = marketId;
        _seedPendingRequest(marketId, requestId, AgentRequestType.JsonApi);

        bytes32 marketBase = keccak256(abi.encode(marketId, uint256(0)));
        bytes32 statusSlot = bytes32(uint256(marketBase) + 10);
        vm.store(address(s_pm), statusSlot, bytes32(uint256(1))); // Resolving

        ISomniaAgents.Response[] memory responses = new ISomniaAgents.Response[](1);
        responses[0] = ISomniaAgents.Response({result: abi.encode(fetchedValue)});
        ISomniaAgents.Request memory req = ISomniaAgents.Request({payload: ""});

        s_mockAgents.callHandleResponse(requestId, responses, ISomniaAgents.ResponseStatus.Success, req);

        // Must compute band the same way the contract does
        uint256 bandLow = threshold - (threshold * bandBps / 10000);
        uint256 bandHigh = threshold + (threshold * bandBps / 10000);

        PredictionMarket.Market memory m = s_pm.getMarket(marketId);
        if (fetchedValue < bandLow) {
            assertEq(uint8(m.status), uint8(MarketStatus.Resolved), "expected Resolved/NO for below-band value");
            assertEq(uint8(m.verdict), uint8(Verdict.NO), "expected NO verdict for below-band value");
        } else if (fetchedValue > bandHigh) {
            assertEq(uint8(m.status), uint8(MarketStatus.Resolved), "expected Resolved/YES for above-band value");
            assertEq(uint8(m.verdict), uint8(Verdict.YES), "expected YES verdict for above-band value");
        } else {
            assertEq(uint8(m.status), uint8(MarketStatus.LLMResolving), "expected LLMResolving for in-band value");
            assertEq(
                uint8(m.pendingAgentType), uint8(AgentRequestType.Llm), "expected Llm pending type after _invokeLlm"
            );
        }
    }

    // ============ _handleLlmResponse Tests ============

    function test_HandleLlmResponse_SettlesYes() public {
        uint256 requestId = 20;
        uint256 marketId = _seedLLMResolvingMarket(requestId);

        ISomniaAgents.Response[] memory responses = new ISomniaAgents.Response[](1);
        responses[0] = ISomniaAgents.Response({result: abi.encode("YES")});
        ISomniaAgents.Request memory req = ISomniaAgents.Request({payload: ""});

        vm.expectEmit(true, false, false, true, address(s_pm));
        emit PredictionMarket.MarketResolved(marketId, Verdict.YES, 0, 0, requestId);

        s_mockAgents.callHandleResponse(requestId, responses, ISomniaAgents.ResponseStatus.Success, req);

        PredictionMarket.Market memory m = s_pm.getMarket(marketId);
        assertEq(uint8(m.status), uint8(MarketStatus.Resolved));
        assertEq(uint8(m.verdict), uint8(Verdict.YES));
        assertTrue(m.resolvedAt > 0);
    }

    function test_HandleLlmResponse_SettlesNo() public {
        uint256 requestId = 21;
        uint256 marketId = _seedLLMResolvingMarket(requestId);

        ISomniaAgents.Response[] memory responses = new ISomniaAgents.Response[](1);
        responses[0] = ISomniaAgents.Response({result: abi.encode("NO")});
        ISomniaAgents.Request memory req = ISomniaAgents.Request({payload: ""});

        vm.expectEmit(true, false, false, true, address(s_pm));
        emit PredictionMarket.MarketResolved(marketId, Verdict.NO, 0, 0, requestId);

        s_mockAgents.callHandleResponse(requestId, responses, ISomniaAgents.ResponseStatus.Success, req);

        PredictionMarket.Market memory m = s_pm.getMarket(marketId);
        assertEq(uint8(m.status), uint8(MarketStatus.Resolved));
        assertEq(uint8(m.verdict), uint8(Verdict.NO));
        assertTrue(m.resolvedAt > 0);
    }

    function test_HandleLlmResponse_RefundsOnInvalid() public {
        uint256 requestId = 22;
        uint256 marketId = _seedLLMResolvingMarket(requestId);

        ISomniaAgents.Response[] memory responses = new ISomniaAgents.Response[](1);
        responses[0] = ISomniaAgents.Response({result: abi.encode("INVALID")});
        ISomniaAgents.Request memory req = ISomniaAgents.Request({payload: ""});

        vm.expectEmit(true, false, false, true, address(s_pm));
        emit PredictionMarket.MarketResolved(marketId, Verdict.INVALID, 0, 0, requestId);

        s_mockAgents.callHandleResponse(requestId, responses, ISomniaAgents.ResponseStatus.Success, req);

        PredictionMarket.Market memory m = s_pm.getMarket(marketId);
        // INVALID → Refunded status, not Resolved or Disputed
        assertEq(uint8(m.status), uint8(MarketStatus.Refunded));
        assertEq(uint8(m.verdict), uint8(Verdict.INVALID));
        assertTrue(m.resolvedAt > 0);
    }

    function test_HandleLlmResponse_MarksDisputedOnFailure() public {
        uint256 requestId = 23;
        uint256 marketId = _seedLLMResolvingMarket(requestId);

        ISomniaAgents.Response[] memory responses = new ISomniaAgents.Response[](0);
        ISomniaAgents.Request memory req = ISomniaAgents.Request({payload: ""});

        vm.expectEmit(true, false, false, true, address(s_pm));
        emit PredictionMarket.ResolutionFailed(marketId, uint8(ISomniaAgents.ResponseStatus.Failed));

        s_mockAgents.callHandleResponse(requestId, responses, ISomniaAgents.ResponseStatus.Failed, req);

        PredictionMarket.Market memory m = s_pm.getMarket(marketId);
        assertEq(uint8(m.status), uint8(MarketStatus.Disputed));
        assertEq(uint8(m.verdict), uint8(Verdict.Unset));
    }

    function test_HandleLlmResponse_MarksDisputedOnUnknownVerdict() public {
        uint256 requestId = 24;
        uint256 marketId = _seedLLMResolvingMarket(requestId);

        ISomniaAgents.Response[] memory responses = new ISomniaAgents.Response[](1);
        responses[0] = ISomniaAgents.Response({result: abi.encode("MAYBE")});
        ISomniaAgents.Request memory req = ISomniaAgents.Request({payload: ""});

        // Unknown verdict emits ResolutionFailed with Success status code (agent "succeeded" but returned garbage)
        vm.expectEmit(true, false, false, true, address(s_pm));
        emit PredictionMarket.ResolutionFailed(marketId, uint8(ISomniaAgents.ResponseStatus.Success));

        s_mockAgents.callHandleResponse(requestId, responses, ISomniaAgents.ResponseStatus.Success, req);

        PredictionMarket.Market memory m = s_pm.getMarket(marketId);
        assertEq(uint8(m.status), uint8(MarketStatus.Disputed));
    }
}
