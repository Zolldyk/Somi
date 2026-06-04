// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

// ============ Imports ============
import {SomniaEventHandler} from "@somnia-chain/reactivity-contracts/contracts/SomniaEventHandler.sol";
import {SomniaExtensions} from "@somnia-chain/reactivity-contracts/contracts/interfaces/SomniaExtensions.sol";

// Layout of Contract: version / imports / errors / events / constructor / _onEvent

/**
 * @title MarketOutcomeSubscriber
 * @author Zoll
 * @notice Example subscriber that mirrors Somi settlement outcomes via Somnia Data Streams (Epic 5 stretch).
 * @dev [Epic 5] Inherits SomniaEventHandler to receive Reactivity callbacks from the Streams proxy.
 *      Subscribes in constructor; emits OutcomeMirrored for every Somi market settled on Streams.
 *      No state, no admin, no other functionality — the simplicity is the demo point.
 */
contract MarketOutcomeSubscriber is SomniaEventHandler {
    // ============ Errors ============

    error MarketOutcomeSubscriber__ZeroAddress();
    error MarketOutcomeSubscriber__InsufficientReactivityFunds(uint256 available, uint256 required);
    error MarketOutcomeSubscriber__AlreadyInitialized();

    // ============ Events ============

    event OutcomeMirrored(uint256 indexed marketId, uint8 verdict, uint64 resolvedAt, uint256 requestId);

    // ============ State ============

    address public immutable i_streamsProxy;
    bytes32 public immutable i_schemaId;
    bool public s_subscribed;

    // ============ Constructor ============

    /// @notice Deploy the subscriber. Fund with ≥32 STT and call `subscribe()` afterwards.
    /// @param _streamsProxy Address of the Somnia Streams contract (0x6AB397FF662e42312c003175DCD76EfF69D048Fc on testnet).
    /// @param _schemaId     Computed schema ID for Somi's outcome schema.
    /// @dev Somnia's CREATE opcode does not transfer msg.value to the contract; subscribing
    ///      requires balance ≥32 STT, so the subscription is registered post-deploy via `subscribe()`.
    constructor(address _streamsProxy, bytes32 _schemaId) payable {
        if (_streamsProxy == address(0)) revert MarketOutcomeSubscriber__ZeroAddress();
        i_streamsProxy = _streamsProxy;
        i_schemaId = _schemaId;
    }

    /// @notice Accept STT top-ups for reactivity balance.
    receive() external payable {}

    /// @notice Register the Reactivity subscription. Callable once after funding ≥32 STT.
    function subscribe() external {
        if (s_subscribed) revert MarketOutcomeSubscriber__AlreadyInitialized();
        if (address(this).balance < 32 ether) {
            revert MarketOutcomeSubscriber__InsufficientReactivityFunds(address(this).balance, 32 ether);
        }
        s_subscribed = true;

        SomniaExtensions.SubscriptionFilter memory filter = SomniaExtensions.SubscriptionFilter({
            eventTopics: [bytes32(0), i_schemaId, bytes32(0), bytes32(0)],
            origin: address(0),
            emitter: i_streamsProxy
        });
        SomniaExtensions.subscribe(address(this), filter, SomniaExtensions.defaultSubscriptionOptions());
    }

    // ============ Internal Functions ============

    /// @notice Decode the Streams schema payload and mirror the outcome event.
    /// @dev Called by the Reactivity precompile when STREAMS_PROXY emits an event matching our subscription.
    ///      Schema: uint256 marketId, string question, uint8 verdict, uint64 resolvedAt, uint256 requestId
    function _onEvent(address, bytes32[] calldata, bytes calldata data) internal override {
        (uint256 marketId, string memory question, uint8 verdict, uint64 resolvedAt, uint256 requestId) =
            abi.decode(data, (uint256, string, uint8, uint64, uint256));
        question; // decoded for schema completeness but not forwarded — suppress linting warnings
        emit OutcomeMirrored(marketId, verdict, resolvedAt, requestId);
    }
}
