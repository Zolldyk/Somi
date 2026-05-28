// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ISomniaAgents} from "../../src/interfaces/ISomniaAgents.sol";
import {PredictionMarket} from "../../src/PredictionMarket.sol";

contract MockSomniaAgents {
    PredictionMarket private s_target;
    uint256 private s_nextRequestId = 1;

    constructor(address target) {
        s_target = PredictionMarket(payable(target));
    }

    function setTarget(address target) external {
        s_target = PredictionMarket(payable(target));
    }

    /// @dev Called by PredictionMarket._invokeLlm (and future _onEvent in Story 1.11).
    ///      Accepts ETH deposit (LLM_DEPOSIT = 0.24 ether) and returns a deterministic requestId.
    function createRequest(
        uint256, // agentId
        address, // callbackContract
        bytes4, // callbackSelector
        bytes memory // payload
    ) external payable returns (uint256 requestId) {
        requestId = s_nextRequestId++;
    }

    function callHandleResponse(
        uint256 requestId,
        ISomniaAgents.Response[] memory responses,
        ISomniaAgents.ResponseStatus status,
        ISomniaAgents.Request memory details
    ) external {
        s_target.handleResponse(requestId, responses, status, details);
    }

    receive() external payable {}
}
