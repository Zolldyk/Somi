// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

interface ISomniaStreams {
    struct DataStream {
        bytes32 id;
        bytes32 schemaId;
        bytes data;
    }

    function esstores(DataStream[] calldata streams) external;
}
