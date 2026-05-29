// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, Vm} from "forge-std/Test.sol";
import {PredictionMarket} from "../src/PredictionMarket.sol";
import {
    MarketStatus,
    Verdict,
    AgentRequestType,
    PredictionMarket__InvalidStateTransition
} from "../src/libraries/MarketLib.sol";
import {
    PredictionMarket__NotWinningPosition, PredictionMarket__NotRefundable
} from "../src/libraries/SettlementLib.sol";
import {ISomniaAgents} from "../src/interfaces/ISomniaAgents.sol";
import {MockSomniaAgents} from "./mocks/MockSomniaAgents.sol";
import {SomniaEventHandler} from "@somnia-chain/reactivity-contracts/contracts/SomniaEventHandler.sol";
import {SomniaExtensions} from "@somnia-chain/reactivity-contracts/contracts/interfaces/SomniaExtensions.sol";
import {ISomniaReactivityPrecompile} from
    "@somnia-chain/reactivity-contracts/contracts/interfaces/ISomniaReactivityPrecompile.sol";
import {MockSomniaReactivityPrecompile} from "./mocks/MockSomniaReactivityPrecompile.sol";

contract PredictionMarketTest is Test {
    PredictionMarket private s_pm;
    MockSomniaAgents private s_mockAgents;
    bool private s_usingMockPrecompile;
    address private constant MOCK_AGENTS = address(0xA9E5);
    address private constant PRECOMPILE = address(0x0100);

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
        // Etch mock precompile at 0x0100 only in unit-test mode (not on Somnia fork)
        if (PRECOMPILE.code.length == 0) {
            s_usingMockPrecompile = true;
            address mockPrecompile = address(new MockSomniaReactivityPrecompile());
            vm.etch(PRECOMPILE, mockPrecompile.code);
        }

        // Step 1: deploy mock with placeholder to break the chicken-and-egg dependency
        s_mockAgents = new MockSomniaAgents(address(0));
        // Step 2: deploy PM with mock's address as the agents contract
        s_pm = new PredictionMarket{value: 50 ether}(address(s_mockAgents));
        // Step 3: wire the mock back to PM
        s_mockAgents.setTarget(address(s_pm));
    }

    receive() external payable {}

    // ============ Happy Path ============

    function test_CreateMarket_HappyPath() public {
        uint64 resolutionTime = uint64(block.timestamp + MIN_LEAD_TIME + 1);

        vm.expectEmit(true, true, false, true, address(s_pm));
        emit PredictionMarket.MarketCreated(1, address(this), QUESTION, resolutionTime);

        vm.expectEmit(true, false, false, true, address(s_pm));
        emit PredictionMarket.ResolutionScheduled(1, 1, resolutionTime); // subscriptionId = 1 from mock

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
        assertEq(m.subscriptionId, 1); // mock returns 1 for first subscription
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

    function test_Constructor_RevertsOnInsufficientDeposit() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                PredictionMarket.PredictionMarket__InsufficientReactivityFunds.selector,
                31 ether,
                32 ether // RESERVE_FLOOR
            )
        );
        new PredictionMarket{value: 31 ether}(address(s_mockAgents));
    }

    function test_Constructor_RevertsOnZeroAgentsAddress() public {
        vm.expectRevert(PredictionMarket.PredictionMarket__ZeroAddress.selector);
        new PredictionMarket{value: RESERVE_FLOOR}(address(0));
    }

    function test_Receive_AcceptsAnonymousTopUp() public {
        uint256 balanceBefore = address(s_pm).balance;
        (bool ok,) = address(s_pm).call{value: 1 ether}("");
        assertTrue(ok, "receive() rejected anonymous top-up");
        assertEq(address(s_pm).balance, balanceBefore + 1 ether);
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
    ///        slot 4: s_requestToMarket, slot 5: s_marketCount, slot 6: s_subscriptionToMarket
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

    /// @dev Creates a market in Resolved state with a given verdict.
    ///      status=Resolved(3), verdict packed into byte 1 of slot +10.
    function _seedResolvedMarket(Verdict verdict) internal returns (uint256 marketId) {
        (marketId,) = _createDefaultMarket();
        bytes32 marketBase = keccak256(abi.encode(marketId, uint256(0)));
        bytes32 statusSlot = bytes32(uint256(marketBase) + 10);
        // Pack: byte 0 = status(Resolved=3), byte 1 = verdict
        vm.store(address(s_pm), statusSlot, bytes32(uint256(3) | (uint256(uint8(verdict)) << 8)));
    }

    /// @dev Creates a market in Refunded (INVALID) or Disputed state.
    ///      Refunded+INVALID: status=4, verdict=3. Disputed+Unset: status=5, verdict=0.
    function _seedRefundableMarket(bool isINVALID) internal returns (uint256 marketId) {
        (marketId,) = _createDefaultMarket();
        bytes32 marketBase = keccak256(abi.encode(marketId, uint256(0)));
        bytes32 statusSlot = bytes32(uint256(marketBase) + 10);
        if (isINVALID) {
            // Refunded=4, INVALID verdict=3
            vm.store(address(s_pm), statusSlot, bytes32(uint256(4) | (uint256(3) << 8)));
        } else {
            // Disputed=5, Unset verdict=0
            vm.store(address(s_pm), statusSlot, bytes32(uint256(5)));
        }
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

    // ============ claim Tests ============

    function test_Claim_YES_HappyPath() public {
        uint256 marketId = _seedResolvedMarket(Verdict.YES);

        // Seed YES bet (side=0)
        bytes32 betSlot = keccak256(
            abi.encode(uint256(0), keccak256(abi.encode(address(this), keccak256(abi.encode(marketId, uint256(1))))))
        );
        vm.store(address(s_pm), betSlot, bytes32(BET_AMOUNT));

        // Seed yesPool + noPool in market struct
        bytes32 marketBase = keccak256(abi.encode(marketId, uint256(0)));
        vm.store(address(s_pm), bytes32(uint256(marketBase) + 8), bytes32(BET_AMOUNT)); // yesPool
        vm.store(address(s_pm), bytes32(uint256(marketBase) + 9), bytes32(uint256(2 ether))); // noPool

        vm.deal(address(s_pm), 50 ether);

        uint256 balanceBefore = address(this).balance;

        vm.expectEmit(true, true, false, true, address(s_pm));
        emit PredictionMarket.Claimed(marketId, address(this), BET_AMOUNT + 2 ether);

        s_pm.claim(marketId);

        // payout = (5e18 * 2e18) / 5e18 + 5e18 = 7e18
        assertEq(address(this).balance - balanceBefore, BET_AMOUNT + 2 ether);
        assertTrue(s_pm.getMarket(marketId).status == MarketStatus.Resolved);
    }

    function test_Claim_NO_HappyPath() public {
        uint256 marketId = _seedResolvedMarket(Verdict.NO);

        // Seed NO bet (side=1)
        bytes32 betSlot = keccak256(
            abi.encode(uint256(1), keccak256(abi.encode(address(this), keccak256(abi.encode(marketId, uint256(1))))))
        );
        vm.store(address(s_pm), betSlot, bytes32(BET_AMOUNT));

        bytes32 marketBase = keccak256(abi.encode(marketId, uint256(0)));
        vm.store(address(s_pm), bytes32(uint256(marketBase) + 8), bytes32(uint256(1 ether))); // yesPool
        vm.store(address(s_pm), bytes32(uint256(marketBase) + 9), bytes32(BET_AMOUNT)); // noPool

        vm.deal(address(s_pm), 50 ether);
        uint256 balanceBefore = address(this).balance;

        s_pm.claim(marketId);

        // payout = (5e18 * 1e18) / 5e18 + 5e18 = 6e18
        assertEq(address(this).balance - balanceBefore, BET_AMOUNT + 1 ether);
    }

    function test_Claim_RevertsWhenNotResolved() public {
        (uint256 marketId,) = _createDefaultMarket(); // status = Open (0)

        vm.expectRevert(
            abi.encodeWithSelector(
                PredictionMarket__InvalidStateTransition.selector, MarketStatus.Open, MarketStatus.Resolved
            )
        );
        s_pm.claim(marketId);
    }

    function test_Claim_RevertsOnAlreadyClaimed() public {
        uint256 marketId = _seedResolvedMarket(Verdict.YES);

        // Seed a YES bet and pool
        bytes32 betSlot = keccak256(
            abi.encode(uint256(0), keccak256(abi.encode(address(this), keccak256(abi.encode(marketId, uint256(1))))))
        );
        vm.store(address(s_pm), betSlot, bytes32(BET_AMOUNT));
        bytes32 marketBase = keccak256(abi.encode(marketId, uint256(0)));
        vm.store(address(s_pm), bytes32(uint256(marketBase) + 8), bytes32(BET_AMOUNT));
        vm.deal(address(s_pm), 50 ether);

        s_pm.claim(marketId); // first claim succeeds

        vm.expectRevert(PredictionMarket.PredictionMarket__AlreadyClaimed.selector);
        s_pm.claim(marketId); // second claim reverts
    }

    function test_Claim_RevertsOnLosingPosition() public {
        uint256 marketId = _seedResolvedMarket(Verdict.YES); // YES wins

        // Seed a NO bet only (loser)
        bytes32 betSlot = keccak256(
            abi.encode(
                uint256(1), // NO side
                keccak256(abi.encode(address(this), keccak256(abi.encode(marketId, uint256(1)))))
            )
        );
        vm.store(address(s_pm), betSlot, bytes32(BET_AMOUNT));
        bytes32 marketBase = keccak256(abi.encode(marketId, uint256(0)));
        vm.store(address(s_pm), bytes32(uint256(marketBase) + 8), bytes32(uint256(1 ether))); // yesPool (someone else)
        vm.store(address(s_pm), bytes32(uint256(marketBase) + 9), bytes32(BET_AMOUNT)); // noPool

        // Caller has no YES stake → calculatePayout reverts NotWinningPosition
        vm.expectRevert(PredictionMarket__NotWinningPosition.selector);
        s_pm.claim(marketId);
    }

    function test_Claim_RevertsOnLosingPositionWhenNoWins() public {
        uint256 marketId = _seedResolvedMarket(Verdict.NO); // NO wins

        // Seed a YES bet only (loser)
        bytes32 betSlot = keccak256(
            abi.encode(
                uint256(0), // YES side
                keccak256(abi.encode(address(this), keccak256(abi.encode(marketId, uint256(1)))))
            )
        );
        vm.store(address(s_pm), betSlot, bytes32(BET_AMOUNT));
        bytes32 marketBase = keccak256(abi.encode(marketId, uint256(0)));
        vm.store(address(s_pm), bytes32(uint256(marketBase) + 8), bytes32(BET_AMOUNT)); // yesPool
        vm.store(address(s_pm), bytes32(uint256(marketBase) + 9), bytes32(uint256(1 ether))); // noPool (someone else)

        // Caller has no NO stake → calculatePayout reverts NotWinningPosition
        vm.expectRevert(PredictionMarket__NotWinningPosition.selector);
        s_pm.claim(marketId);
    }

    // ============ refund Tests ============

    function test_Refund_INVALID_HappyPath() public {
        uint256 marketId = _seedRefundableMarket(true); // Refunded+INVALID

        bytes32 yesBetSlot = keccak256(
            abi.encode(uint256(0), keccak256(abi.encode(address(this), keccak256(abi.encode(marketId, uint256(1))))))
        );
        bytes32 noBetSlot = keccak256(
            abi.encode(uint256(1), keccak256(abi.encode(address(this), keccak256(abi.encode(marketId, uint256(1))))))
        );
        vm.store(address(s_pm), yesBetSlot, bytes32(uint256(3 ether)));
        vm.store(address(s_pm), noBetSlot, bytes32(uint256(2 ether)));
        vm.deal(address(s_pm), 50 ether);

        uint256 balanceBefore = address(this).balance;

        vm.expectEmit(true, true, false, true, address(s_pm));
        emit PredictionMarket.Refunded(marketId, address(this), 5 ether);

        s_pm.refund(marketId);

        assertEq(address(this).balance - balanceBefore, 5 ether);
    }

    function test_Refund_Disputed_HappyPath() public {
        uint256 marketId = _seedRefundableMarket(false); // Disputed+Unset

        bytes32 yesBetSlot = keccak256(
            abi.encode(uint256(0), keccak256(abi.encode(address(this), keccak256(abi.encode(marketId, uint256(1))))))
        );
        vm.store(address(s_pm), yesBetSlot, bytes32(BET_AMOUNT));
        vm.deal(address(s_pm), 50 ether);

        uint256 balanceBefore = address(this).balance;
        s_pm.refund(marketId);

        assertEq(address(this).balance - balanceBefore, BET_AMOUNT);
    }

    function test_Refund_BothSides() public {
        uint256 marketId = _seedRefundableMarket(true);

        bytes32 yesBetSlot = keccak256(
            abi.encode(uint256(0), keccak256(abi.encode(address(this), keccak256(abi.encode(marketId, uint256(1))))))
        );
        bytes32 noBetSlot = keccak256(
            abi.encode(uint256(1), keccak256(abi.encode(address(this), keccak256(abi.encode(marketId, uint256(1))))))
        );
        vm.store(address(s_pm), yesBetSlot, bytes32(uint256(3 ether)));
        vm.store(address(s_pm), noBetSlot, bytes32(uint256(4 ether)));
        vm.deal(address(s_pm), 50 ether);

        uint256 balanceBefore = address(this).balance;
        s_pm.refund(marketId);

        assertEq(address(this).balance - balanceBefore, 7 ether);
    }

    function test_Refund_RevertsWhenResolved() public {
        uint256 marketId = _seedResolvedMarket(Verdict.YES); // Resolved — not refundable

        vm.expectRevert(
            abi.encodeWithSelector(
                PredictionMarket__InvalidStateTransition.selector, MarketStatus.Resolved, MarketStatus.Refunded
            )
        );
        s_pm.refund(marketId);
    }

    function test_Refund_RevertsWhenOpenResolvingOrLLMResolving() public {
        (uint256 openMarketId,) = _createDefaultMarket();

        vm.expectRevert(
            abi.encodeWithSelector(
                PredictionMarket__InvalidStateTransition.selector, MarketStatus.Open, MarketStatus.Refunded
            )
        );
        s_pm.refund(openMarketId);

        uint256 resolvingMarketId = _seedResolvingMarket(101);

        vm.expectRevert(
            abi.encodeWithSelector(
                PredictionMarket__InvalidStateTransition.selector, MarketStatus.Resolving, MarketStatus.Refunded
            )
        );
        s_pm.refund(resolvingMarketId);

        uint256 llmResolvingMarketId = _seedLLMResolvingMarket(102);

        vm.expectRevert(
            abi.encodeWithSelector(
                PredictionMarket__InvalidStateTransition.selector, MarketStatus.LLMResolving, MarketStatus.Refunded
            )
        );
        s_pm.refund(llmResolvingMarketId);
    }

    function test_Refund_RevertsOnAlreadyRefunded() public {
        uint256 marketId = _seedRefundableMarket(true);

        bytes32 yesBetSlot = keccak256(
            abi.encode(uint256(0), keccak256(abi.encode(address(this), keccak256(abi.encode(marketId, uint256(1))))))
        );
        vm.store(address(s_pm), yesBetSlot, bytes32(BET_AMOUNT));
        vm.deal(address(s_pm), 50 ether);

        s_pm.refund(marketId); // first succeeds

        vm.expectRevert(PredictionMarket.PredictionMarket__AlreadyRefunded.selector);
        s_pm.refund(marketId); // second reverts
    }

    function test_Refund_RevertsOnNoBet() public {
        uint256 marketId = _seedRefundableMarket(true); // no bets seeded

        vm.expectRevert(PredictionMarket__NotRefundable.selector);
        s_pm.refund(marketId);
    }

    // ============ Fuzz Tests — claim & refund ============

    function testFuzz_Claim_PreservesPotConservation(uint256 yesStake1, uint256 yesStake2, uint256 noStake) public {
        yesStake1 = bound(yesStake1, MIN_BET, 50 ether);
        yesStake2 = bound(yesStake2, MIN_BET, 50 ether);
        noStake = bound(noStake, 0, 50 ether); // noPool may be zero

        (uint256 marketId,) = _createDefaultMarket();

        address bettor1 = address(0x1001);
        address bettor2 = address(0x1002);
        address noBettor = address(0x1003);

        vm.deal(bettor1, yesStake1);
        vm.deal(bettor2, yesStake2);
        vm.deal(noBettor, noStake + 1 ether);

        vm.prank(bettor1);
        s_pm.placeBet{value: yesStake1}(marketId, 0); // YES

        vm.prank(bettor2);
        s_pm.placeBet{value: yesStake2}(marketId, 0); // YES

        if (noStake >= MIN_BET) {
            vm.prank(noBettor);
            s_pm.placeBet{value: noStake}(marketId, 1); // NO
        }

        // Settle: Resolved + YES via vm.store
        bytes32 marketBase = keccak256(abi.encode(marketId, uint256(0)));
        bytes32 statusSlot = bytes32(uint256(marketBase) + 10);
        vm.store(address(s_pm), statusSlot, bytes32(uint256(3) | (uint256(1) << 8)));

        PredictionMarket.Market memory m = s_pm.getMarket(marketId);
        uint256 totalPot = m.yesPool + m.noPool;

        uint256 b1Before = bettor1.balance;
        uint256 b2Before = bettor2.balance;

        vm.prank(bettor1);
        s_pm.claim(marketId);
        vm.prank(bettor2);
        s_pm.claim(marketId);

        uint256 payout1 = bettor1.balance - b1Before;
        uint256 payout2 = bettor2.balance - b2Before;
        uint256 totalPayout = payout1 + payout2;

        // Pot conservation: total paid out never exceeds total staked
        assertLe(totalPayout, totalPot, "payouts must not exceed total pot");
        // Dust from integer division: at most (numWinners - 1) wei remains
        assertGe(totalPayout + 1, totalPot > 0 ? totalPot - 1 : 0, "excessive dust in contract");
    }

    // ============ _onEvent Tests ============

    function test_OnEvent_OpenToResolving_HappyPath() public {
        (uint256 marketId,) = _createDefaultMarket();
        uint256 subscriptionId = s_pm.getMarket(marketId).subscriptionId; // = 1 from mock

        // First createRequest in this test returns requestId = 1 (s_mockAgents.s_nextRequestId = 1)
        vm.expectEmit(true, true, false, false, address(s_pm));
        emit PredictionMarket.ResolutionInitiated(marketId, 1);

        bytes32[] memory topics = new bytes32[](2);
        topics[0] = ISomniaReactivityPrecompile.Schedule.selector;
        topics[1] = bytes32(uint256(s_pm.getMarket(marketId).resolutionTime) * 1000);

        vm.prank(PRECOMPILE);
        s_pm.onEvent(PRECOMPILE, topics, abi.encode(subscriptionId));

        PredictionMarket.Market memory m = s_pm.getMarket(marketId);
        assertEq(uint8(m.status), uint8(MarketStatus.Resolving));
        assertEq(m.pendingRequestId, 1);
        assertEq(uint8(m.pendingAgentType), uint8(AgentRequestType.JsonApi));
    }

    function test_OnEvent_EmitsResolutionDeferred_WhenInsufficientBalance() public {
        (uint256 marketId,) = _createDefaultMarket();
        uint256 subscriptionId = s_pm.getMarket(marketId).subscriptionId;

        // Drain below JSON_DEPOSIT (0.12 ether)
        vm.deal(address(s_pm), 0.05 ether);

        vm.expectEmit(true, false, false, false, address(s_pm));
        emit PredictionMarket.ResolutionDeferred(marketId);

        vm.prank(PRECOMPILE);
        s_pm.onEvent(PRECOMPILE, new bytes32[](0), abi.encode(subscriptionId));

        // No state mutation — market stays Open
        assertEq(uint8(s_pm.getMarket(marketId).status), uint8(MarketStatus.Open));
        assertEq(s_pm.getMarket(marketId).pendingRequestId, 0);
    }

    function test_OnEvent_RevertsWhenNotPrecompile() public {
        vm.prank(address(0xBEEF));
        vm.expectRevert(SomniaEventHandler.OnlyReactivityPrecompile.selector);
        s_pm.onEvent(address(0), new bytes32[](0), "");
    }

    function test_ReactivityFlow_OpenToResolving_ForkTest() public {
        // Skip when not running with a Somnia testnet fork
        if (s_usingMockPrecompile) {
            vm.skip(true);
            return;
        }
        // On a Somnia fork, setUp does NOT etch the mock; real precompile at 0x0100 is used.
        (uint256 marketId,) = _createDefaultMarket();

        PredictionMarket.Market memory m = s_pm.getMarket(marketId);
        assertGt(m.subscriptionId, 0); // real precompile returned a real subscriptionId

        // Advance time past resolutionTime
        vm.warp(m.resolutionTime + 1);

        // Manually simulate the precompile callback (vm.warp does not auto-fire subscriptions)
        bytes32[] memory topics = new bytes32[](2);
        topics[0] = ISomniaReactivityPrecompile.Schedule.selector;
        topics[1] = bytes32(uint256(m.resolutionTime) * 1000);

        vm.prank(PRECOMPILE);
        s_pm.onEvent(PRECOMPILE, topics, abi.encode(m.subscriptionId));

        assertEq(uint8(s_pm.getMarket(marketId).status), uint8(MarketStatus.Resolving));
    }

    // ============ Fuzz Tests — claim & refund ============

    function testFuzz_Refund_SumEqualsTotalStaked(uint256 yesStake1, uint256 yesStake2, uint256 noStake1) public {
        yesStake1 = bound(yesStake1, MIN_BET, 50 ether);
        yesStake2 = bound(yesStake2, MIN_BET, 50 ether);
        noStake1 = bound(noStake1, MIN_BET, 50 ether);

        (uint256 marketId,) = _createDefaultMarket();

        address bettor1 = address(0x2001);
        address bettor2 = address(0x2002);
        address bettor3 = address(0x2003);

        vm.deal(bettor1, yesStake1);
        vm.deal(bettor2, yesStake2);
        vm.deal(bettor3, noStake1);

        vm.prank(bettor1);
        s_pm.placeBet{value: yesStake1}(marketId, 0);
        vm.prank(bettor2);
        s_pm.placeBet{value: yesStake2}(marketId, 0);
        vm.prank(bettor3);
        s_pm.placeBet{value: noStake1}(marketId, 1);

        // Set to Refunded + INVALID
        bytes32 marketBase = keccak256(abi.encode(marketId, uint256(0)));
        bytes32 statusSlot = bytes32(uint256(marketBase) + 10);
        vm.store(address(s_pm), statusSlot, bytes32(uint256(4) | (uint256(3) << 8)));

        PredictionMarket.Market memory m = s_pm.getMarket(marketId);
        uint256 totalStaked = m.yesPool + m.noPool;

        uint256 b1Before = bettor1.balance;
        uint256 b2Before = bettor2.balance;
        uint256 b3Before = bettor3.balance;

        vm.prank(bettor1);
        s_pm.refund(marketId);
        vm.prank(bettor2);
        s_pm.refund(marketId);
        vm.prank(bettor3);
        s_pm.refund(marketId);

        uint256 totalRefunded =
            (bettor1.balance - b1Before) + (bettor2.balance - b2Before) + (bettor3.balance - b3Before);

        // Refund is full-stake recovery; no integer division — exact equality
        assertEq(totalRefunded, totalStaked, "total refunded must equal total staked");
    }
}
