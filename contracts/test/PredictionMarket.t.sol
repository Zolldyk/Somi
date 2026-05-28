// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, Vm} from "forge-std/Test.sol";
import {PredictionMarket} from "../src/PredictionMarket.sol";
import {MarketStatus, Verdict, AgentRequestType} from "../src/libraries/MarketLib.sol";

contract PredictionMarketTest is Test {
    PredictionMarket private s_pm;
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
        s_pm = new PredictionMarket{value: 50 ether}(MOCK_AGENTS);
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
}
