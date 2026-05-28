// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

// ============ Type declarations ============

enum MarketStatus {
    Open,
    Resolving,
    LLMResolving,
    Resolved,
    Refunded,
    Disputed
}

enum Verdict {
    Unset,
    YES,
    NO,
    INVALID
}

enum AgentRequestType {
    None,
    JsonApi,
    Llm
}

// ============ Errors ============

error PredictionMarket__InvalidStateTransition(MarketStatus actual, MarketStatus expected);

/**
 * @title MarketLib
 * @author Zoll
 * @notice Pure state-transition validators and view helpers for PredictionMarket.
 * @dev All functions are pure; no storage access, no events, no payable.
 *      Called explicitly as MarketLib.fn(...) — no `using for` per AR-17.
 */
library MarketLib {
    // ============ State-Transition Guards ============

    /// @notice Reverts if `actual` status differs from `expected`.
    /// @param actual   Current market status from storage.
    /// @param expected The status required to proceed.
    /// @dev Used in every state-mutating function of PredictionMarket.
    function requireStatus(MarketStatus actual, MarketStatus expected) internal pure {
        if (actual != expected) {
            revert PredictionMarket__InvalidStateTransition(actual, expected);
        }
    }

    // ============ View Helpers ============

    /// @notice Returns true when a market is in a state that allows claims (Resolved only).
    function isClaimable(MarketStatus status) internal pure returns (bool) {
        return status == MarketStatus.Resolved;
    }

    /// @notice Returns true when a market is in a state that allows refunds (Refunded or Disputed).
    /// @param verdict Not gating the bool; passed for caller convenience to distinguish
    ///                INVALID philosophy copy (Refunded+INVALID) from technical failure copy (Disputed+Unset).
    function isRefundable(MarketStatus status, Verdict verdict) internal pure returns (bool) {
        // silence unused-variable warning
        verdict;
        return status == MarketStatus.Refunded || status == MarketStatus.Disputed;
    }

    /// @notice Returns true for exactly the 7 legal state transitions in the locked matrix.
    /// @dev Covers: Open→Resolving, Resolving→{Resolved,LLMResolving,Disputed},
    ///              LLMResolving→{Resolved,Refunded,Disputed}. All others return false.
    function canTransitionTo(MarketStatus from, MarketStatus to) internal pure returns (bool) {
        if (from == MarketStatus.Open) return to == MarketStatus.Resolving;
        if (from == MarketStatus.Resolving) {
            return to == MarketStatus.Resolved || to == MarketStatus.LLMResolving || to == MarketStatus.Disputed;
        }
        if (from == MarketStatus.LLMResolving) {
            return to == MarketStatus.Resolved || to == MarketStatus.Refunded || to == MarketStatus.Disputed;
        }
        return false; // Resolved, Refunded, Disputed are terminal — no outgoing transitions
    }
}
