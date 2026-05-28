// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

// ============ Errors ============

error PredictionMarket__NotWinningPosition();
error PredictionMarket__NotRefundable();

/**
 * @title SettlementLib
 * @author Zoll
 * @notice Pure payout and refund math for PredictionMarket.
 * @dev All functions are pure; no storage access, no events, no payable.
 *      Called explicitly as SettlementLib.fn(...) — no `using for` per AR-17.
 *      Multiply before divide throughout to preserve precision.
 */
library SettlementLib {
    // ============ Payout Math ============

    /// @notice Compute winner's payout: proportional share of losing pool + original stake.
    /// @param myWinningStake  Caller's stake on the winning side.
    /// @param winningPool     Total amount staked on the winning side.
    /// @param losingPool      Total amount staked on the losing side.
    /// @return payout         myWinningStake + (myWinningStake * losingPool) / winningPool
    /// @dev Reverts if myWinningStake is zero. Multiply before divide to avoid precision loss.
    ///      Integer division floors; dust (unreachable wei) stays in the contract — pot is conserved.
    function calculatePayout(uint256 myWinningStake, uint256 winningPool, uint256 losingPool)
        internal
        pure
        returns (uint256)
    {
        if (myWinningStake == 0) revert PredictionMarket__NotWinningPosition();
        return (myWinningStake * losingPool) / winningPool + myWinningStake;
    }

    // ============ Refund Math ============

    /// @notice Compute INVALID/Disputed refund: full recovery of stakes on both sides.
    /// @param myYesStake  Caller's stake on the YES side (may be zero).
    /// @param myNoStake   Caller's stake on the NO side (may be zero).
    /// @return refund     myYesStake + myNoStake
    /// @dev Reverts if both stakes are zero. v1: full refund, no house cut.
    function calculateRefund(uint256 myYesStake, uint256 myNoStake) internal pure returns (uint256) {
        if (myYesStake == 0 && myNoStake == 0) revert PredictionMarket__NotRefundable();
        return myYesStake + myNoStake;
    }
}
