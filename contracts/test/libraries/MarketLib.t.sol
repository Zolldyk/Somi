// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {MarketLib, MarketStatus, Verdict} from "../../src/libraries/MarketLib.sol";
import {PredictionMarket__InvalidStateTransition} from "../../src/libraries/MarketLib.sol";

/// @dev Wrapper so vm.expectRevert can intercept requireStatus (internal → external subcall).
contract RequireStatusWrapper {
    function call(MarketStatus actual, MarketStatus expected) external pure {
        MarketLib.requireStatus(actual, expected);
    }
}

contract MarketLibTest is Test {
    RequireStatusWrapper private _wrapper;

    function setUp() public {
        _wrapper = new RequireStatusWrapper();
    }

    // ============ requireStatus ============

    function test_RequireStatus_NoRevertWhenMatch() public pure {
        MarketLib.requireStatus(MarketStatus.Open, MarketStatus.Open);
        MarketLib.requireStatus(MarketStatus.Resolving, MarketStatus.Resolving);
        MarketLib.requireStatus(MarketStatus.Resolved, MarketStatus.Resolved);
    }

    function test_RequireStatus_RevertsOnMismatch() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                PredictionMarket__InvalidStateTransition.selector, MarketStatus.Open, MarketStatus.Resolving
            )
        );
        _wrapper.call(MarketStatus.Open, MarketStatus.Resolving);
    }

    // ============ canTransitionTo — legal transitions (7) ============

    function test_CanTransitionTo_OpenToResolving() public pure {
        assertTrue(MarketLib.canTransitionTo(MarketStatus.Open, MarketStatus.Resolving));
    }

    function test_CanTransitionTo_ResolvingToResolved() public pure {
        assertTrue(MarketLib.canTransitionTo(MarketStatus.Resolving, MarketStatus.Resolved));
    }

    function test_CanTransitionTo_ResolvingToLLMResolving() public pure {
        assertTrue(MarketLib.canTransitionTo(MarketStatus.Resolving, MarketStatus.LLMResolving));
    }

    function test_CanTransitionTo_ResolvingToDisputed() public pure {
        assertTrue(MarketLib.canTransitionTo(MarketStatus.Resolving, MarketStatus.Disputed));
    }

    function test_CanTransitionTo_LLMResolvingToResolved() public pure {
        assertTrue(MarketLib.canTransitionTo(MarketStatus.LLMResolving, MarketStatus.Resolved));
    }

    function test_CanTransitionTo_LLMResolvingToRefunded() public pure {
        assertTrue(MarketLib.canTransitionTo(MarketStatus.LLMResolving, MarketStatus.Refunded));
    }

    function test_CanTransitionTo_LLMResolvingToDisputed() public pure {
        assertTrue(MarketLib.canTransitionTo(MarketStatus.LLMResolving, MarketStatus.Disputed));
    }

    // ============ canTransitionTo — illegal transitions (branch coverage) ============

    function test_CanTransitionTo_OpenToOpen_False() public pure {
        assertFalse(MarketLib.canTransitionTo(MarketStatus.Open, MarketStatus.Open));
    }

    function test_CanTransitionTo_OpenToResolved_False() public pure {
        assertFalse(MarketLib.canTransitionTo(MarketStatus.Open, MarketStatus.Resolved));
    }

    function test_CanTransitionTo_OpenToDisputed_False() public pure {
        assertFalse(MarketLib.canTransitionTo(MarketStatus.Open, MarketStatus.Disputed));
    }

    function test_CanTransitionTo_ResolvingToOpen_False() public pure {
        assertFalse(MarketLib.canTransitionTo(MarketStatus.Resolving, MarketStatus.Open));
    }

    function test_CanTransitionTo_ResolvingToRefunded_False() public pure {
        assertFalse(MarketLib.canTransitionTo(MarketStatus.Resolving, MarketStatus.Refunded));
    }

    function test_CanTransitionTo_LLMResolvingToOpen_False() public pure {
        assertFalse(MarketLib.canTransitionTo(MarketStatus.LLMResolving, MarketStatus.Open));
    }

    function test_CanTransitionTo_LLMResolvingToResolving_False() public pure {
        assertFalse(MarketLib.canTransitionTo(MarketStatus.LLMResolving, MarketStatus.Resolving));
    }

    function test_CanTransitionTo_ResolvedToAnything_False() public pure {
        assertFalse(MarketLib.canTransitionTo(MarketStatus.Resolved, MarketStatus.Open));
        assertFalse(MarketLib.canTransitionTo(MarketStatus.Resolved, MarketStatus.Resolving));
        assertFalse(MarketLib.canTransitionTo(MarketStatus.Resolved, MarketStatus.LLMResolving));
        assertFalse(MarketLib.canTransitionTo(MarketStatus.Resolved, MarketStatus.Resolved));
        assertFalse(MarketLib.canTransitionTo(MarketStatus.Resolved, MarketStatus.Refunded));
        assertFalse(MarketLib.canTransitionTo(MarketStatus.Resolved, MarketStatus.Disputed));
    }

    function test_CanTransitionTo_RefundedToAnything_False() public pure {
        assertFalse(MarketLib.canTransitionTo(MarketStatus.Refunded, MarketStatus.Open));
        assertFalse(MarketLib.canTransitionTo(MarketStatus.Refunded, MarketStatus.Resolving));
        assertFalse(MarketLib.canTransitionTo(MarketStatus.Refunded, MarketStatus.LLMResolving));
        assertFalse(MarketLib.canTransitionTo(MarketStatus.Refunded, MarketStatus.Resolved));
        assertFalse(MarketLib.canTransitionTo(MarketStatus.Refunded, MarketStatus.Refunded));
        assertFalse(MarketLib.canTransitionTo(MarketStatus.Refunded, MarketStatus.Disputed));
    }

    function test_CanTransitionTo_DisputedToAnything_False() public pure {
        assertFalse(MarketLib.canTransitionTo(MarketStatus.Disputed, MarketStatus.Open));
        assertFalse(MarketLib.canTransitionTo(MarketStatus.Disputed, MarketStatus.Resolving));
        assertFalse(MarketLib.canTransitionTo(MarketStatus.Disputed, MarketStatus.LLMResolving));
        assertFalse(MarketLib.canTransitionTo(MarketStatus.Disputed, MarketStatus.Resolved));
        assertFalse(MarketLib.canTransitionTo(MarketStatus.Disputed, MarketStatus.Refunded));
        assertFalse(MarketLib.canTransitionTo(MarketStatus.Disputed, MarketStatus.Disputed));
    }

    // ============ isClaimable ============

    function test_IsClaimable_TrueOnlyForResolved() public pure {
        assertTrue(MarketLib.isClaimable(MarketStatus.Resolved));
    }

    function test_IsClaimable_FalseForOpen() public pure {
        assertFalse(MarketLib.isClaimable(MarketStatus.Open));
    }

    function test_IsClaimable_FalseForResolving() public pure {
        assertFalse(MarketLib.isClaimable(MarketStatus.Resolving));
    }

    function test_IsClaimable_FalseForLLMResolving() public pure {
        assertFalse(MarketLib.isClaimable(MarketStatus.LLMResolving));
    }

    function test_IsClaimable_FalseForRefunded() public pure {
        assertFalse(MarketLib.isClaimable(MarketStatus.Refunded));
    }

    function test_IsClaimable_FalseForDisputed() public pure {
        assertFalse(MarketLib.isClaimable(MarketStatus.Disputed));
    }

    // ============ isRefundable ============

    function test_IsRefundable_TrueForRefundedInvalid() public pure {
        assertTrue(MarketLib.isRefundable(MarketStatus.Refunded, Verdict.INVALID));
    }

    function test_IsRefundable_TrueForDisputedUnset() public pure {
        assertTrue(MarketLib.isRefundable(MarketStatus.Disputed, Verdict.Unset));
    }

    function test_IsRefundable_FalseForResolved() public pure {
        assertFalse(MarketLib.isRefundable(MarketStatus.Resolved, Verdict.YES));
    }

    function test_IsRefundable_FalseForOpen() public pure {
        assertFalse(MarketLib.isRefundable(MarketStatus.Open, Verdict.Unset));
    }

    function test_IsRefundable_FalseForResolving() public pure {
        assertFalse(MarketLib.isRefundable(MarketStatus.Resolving, Verdict.Unset));
    }

    function test_IsRefundable_FalseForLLMResolving() public pure {
        assertFalse(MarketLib.isRefundable(MarketStatus.LLMResolving, Verdict.Unset));
    }

    function test_IsRefundable_AllStatusesAndVerdicts() public pure {
        for (uint8 status_ = 0; status_ < 6; status_++) {
            for (uint8 verdict_ = 0; verdict_ < 4; verdict_++) {
                MarketStatus status = MarketStatus(status_);
                Verdict verdict = Verdict(verdict_);

                bool expected = status == MarketStatus.Refunded || status == MarketStatus.Disputed;
                assertEq(MarketLib.isRefundable(status, verdict), expected);
            }
        }
    }

    // ============ fuzz ============

    function testFuzz_CanTransitionTo_OnlyMatrixEntries(uint8 from_, uint8 to_) public pure {
        from_ = uint8(bound(from_, 0, 5));
        to_ = uint8(bound(to_, 0, 5));
        MarketStatus from = MarketStatus(from_);
        MarketStatus to = MarketStatus(to_);

        bool result = MarketLib.canTransitionTo(from, to);

        bool expected = (
            (from == MarketStatus.Open && to == MarketStatus.Resolving)
                || (from == MarketStatus.Resolving && to == MarketStatus.Resolved)
                || (from == MarketStatus.Resolving && to == MarketStatus.LLMResolving)
                || (from == MarketStatus.Resolving && to == MarketStatus.Disputed)
                || (from == MarketStatus.LLMResolving && to == MarketStatus.Resolved)
                || (from == MarketStatus.LLMResolving && to == MarketStatus.Refunded)
                || (from == MarketStatus.LLMResolving && to == MarketStatus.Disputed)
        );

        assertEq(result, expected);
    }
}
