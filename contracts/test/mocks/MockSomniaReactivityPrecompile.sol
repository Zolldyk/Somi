// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ISomniaReactivityPrecompile} from
    "@somnia-chain/reactivity-contracts/contracts/interfaces/ISomniaReactivityPrecompile.sol";

contract MockSomniaReactivityPrecompile {
    uint256 private s_nextSubId;

    function subscribe(ISomniaReactivityPrecompile.SubscriptionData calldata)
        external
        returns (uint256 subscriptionId)
    {
        return ++s_nextSubId; // slot 0 starts at 0; first call returns 1
    }

    function unsubscribe(uint256) external {}
}
