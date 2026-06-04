// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {MarketOutcomeSubscriber} from "../src/MarketOutcomeSubscriber.sol";
import {MockSomniaReactivityPrecompile} from "./mocks/MockSomniaReactivityPrecompile.sol";

contract MarketOutcomeSubscriberTest is Test {
    MarketOutcomeSubscriber private s_subscriber;

    address private constant PRECOMPILE = address(0x0100);
    address private constant STREAMS_PROXY = 0x6AB397FF662e42312c003175DCD76EfF69D048Fc;
    bytes32 private constant SCHEMA_ID = bytes32(uint256(0xdeadbeef));

    function setUp() public {
        if (PRECOMPILE.code.length == 0) {
            address mockPrecompile = address(new MockSomniaReactivityPrecompile());
            vm.etch(PRECOMPILE, mockPrecompile.code);
        }
    }

    function test_Deploy_Succeeds() public {
        s_subscriber = new MarketOutcomeSubscriber(STREAMS_PROXY, SCHEMA_ID);
        assertEq(s_subscriber.i_streamsProxy(), STREAMS_PROXY);
        assertEq(s_subscriber.i_schemaId(), SCHEMA_ID);
        assertFalse(s_subscriber.s_subscribed());
    }

    function test_Deploy_RevertsOnZeroAddress() public {
        vm.expectRevert(MarketOutcomeSubscriber.MarketOutcomeSubscriber__ZeroAddress.selector);
        new MarketOutcomeSubscriber(address(0), SCHEMA_ID);
    }

    function test_Subscribe_RevertsOnInsufficientFunds() public {
        s_subscriber = new MarketOutcomeSubscriber(STREAMS_PROXY, SCHEMA_ID);
        vm.deal(address(s_subscriber), 31 ether);

        vm.expectRevert(
            abi.encodeWithSelector(
                MarketOutcomeSubscriber.MarketOutcomeSubscriber__InsufficientReactivityFunds.selector,
                31 ether,
                32 ether
            )
        );
        s_subscriber.subscribe();
    }

    function test_Subscribe_RevertsOnDoubleCall() public {
        s_subscriber = new MarketOutcomeSubscriber(STREAMS_PROXY, SCHEMA_ID);
        vm.deal(address(s_subscriber), 50 ether);
        s_subscriber.subscribe();

        vm.expectRevert(MarketOutcomeSubscriber.MarketOutcomeSubscriber__AlreadyInitialized.selector);
        s_subscriber.subscribe();
    }

    function test_Subscribe_SetsFlag() public {
        s_subscriber = new MarketOutcomeSubscriber(STREAMS_PROXY, SCHEMA_ID);
        vm.deal(address(s_subscriber), 50 ether);
        s_subscriber.subscribe();
        assertTrue(s_subscriber.s_subscribed());
    }

    function test_Receive_AcceptsTopUp() public {
        s_subscriber = new MarketOutcomeSubscriber(STREAMS_PROXY, SCHEMA_ID);
        (bool ok,) = address(s_subscriber).call{value: 10 ether}("");
        assertTrue(ok);
        assertEq(address(s_subscriber).balance, 10 ether);
    }

    function test_OnEvent_EmitsOutcomeMirrored() public {
        s_subscriber = new MarketOutcomeSubscriber(STREAMS_PROXY, SCHEMA_ID);

        uint256 marketId = 42;
        uint8 verdict = 1; // YES
        uint64 resolvedAt = uint64(block.timestamp);
        uint256 requestId = 999;

        bytes memory payload = abi.encode(marketId, "Will BTC > 110k?", verdict, resolvedAt, requestId);

        vm.expectEmit(true, false, false, true, address(s_subscriber));
        emit MarketOutcomeSubscriber.OutcomeMirrored(marketId, verdict, resolvedAt, requestId);

        vm.prank(PRECOMPILE);
        s_subscriber.onEvent(address(0), new bytes32[](0), payload);
    }
}
