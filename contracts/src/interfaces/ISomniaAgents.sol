// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

interface ISomniaAgents {
    struct Response {
        bytes result;
    }

    enum ResponseStatus {
        Success,
        Failed,
        TimedOut
    }

    struct Request {
        bytes payload;
    }

    function createRequest(uint256 agentId, address callbackContract, bytes4 callbackSelector, bytes memory payload)
        external
        payable
        returns (uint256 requestId);
}
