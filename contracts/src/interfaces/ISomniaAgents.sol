// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title ISomniaAgents
/// @notice Interface for the Somnia Agents platform — request creation and the response callback ABI.
/// @dev The callback structs/enums mirror the platform's on-chain wire format exactly (verified field-by-field
///      against a live testnet callback). The platform invokes the registered selector with
///      `handleResponse(uint256, Response[], ResponseStatus, Request)`; a mismatch in these definitions
///      causes the callback to revert on ABI decode (the market would stay Resolving forever).
interface ISomniaAgents {
    enum ConsensusType {
        Majority,
        Threshold
    }

    enum ResponseStatus {
        None, // 0 — uninitialized
        Pending, // 1 — awaiting responses
        Success, // 2 — consensus reached
        Failed, // 3 — validators reported failure
        TimedOut // 4 — request timed out
    }

    struct Response {
        address validator;
        bytes result;
        ResponseStatus status;
        uint256 receipt;
        uint256 timestamp;
        uint256 executionCost;
    }

    struct Request {
        uint256 id;
        address requester;
        address callbackAddress;
        bytes4 callbackSelector;
        address[] subcommittee;
        Response[] responses;
        uint256 responseCount;
        uint256 failureCount;
        uint256 threshold;
        uint256 createdAt;
        uint256 deadline;
        ResponseStatus status;
        ConsensusType consensusType;
        uint256 remainingBudget;
        uint256 perAgentBudget;
    }

    function createRequest(uint256 agentId, address callbackContract, bytes4 callbackSelector, bytes memory payload)
        external
        payable
        returns (uint256 requestId);
}
