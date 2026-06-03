// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ISomniaStreams} from "../../src/interfaces/ISomniaStreams.sol";

contract MockSomniaStreams {
    bool public shouldRevert;

    function setShouldRevert(bool v) external {
        shouldRevert = v;
    }

    function esstores(ISomniaStreams.DataStream[] calldata) external view {
        if (shouldRevert) revert("streams-error");
    }
}
