// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {SettlementLib} from "../../src/libraries/SettlementLib.sol";
import {
    PredictionMarket__NotWinningPosition,
    PredictionMarket__NotRefundable
} from "../../src/libraries/SettlementLib.sol";

/// @dev Wrapper so vm.expectRevert can intercept pure library calls via external subcall.
contract SettlementLibWrapper {
    function callCalculatePayout(uint256 myWinningStake, uint256 winningPool, uint256 losingPool)
        external
        pure
        returns (uint256)
    {
        return SettlementLib.calculatePayout(myWinningStake, winningPool, losingPool);
    }

    function callCalculateRefund(uint256 myYesStake, uint256 myNoStake) external pure returns (uint256) {
        return SettlementLib.calculateRefund(myYesStake, myNoStake);
    }
}

contract SettlementLibTest is Test {
    SettlementLibWrapper private _wrapper;

    function setUp() public {
        _wrapper = new SettlementLibWrapper();
    }

    // ============ calculatePayout — unit tests ============

    function test_CalculatePayout_LoneWinner() public pure {
        // Sole bettor: myStake == winningPool, losingPool > 0
        // payout = (100 * 50) / 100 + 100 = 50 + 100 = 150 = winningPool + losingPool
        uint256 payout = SettlementLib.calculatePayout(100 ether, 100 ether, 50 ether);
        assertEq(payout, 150 ether);
    }

    function test_CalculatePayout_WinnerTakesAll_EmptyLosingPool() public pure {
        // losingPool == 0: payout = (stake * 0) / winningPool + stake = stake
        uint256 payout = SettlementLib.calculatePayout(60 ether, 100 ether, 0);
        assertEq(payout, 60 ether);
    }

    function test_CalculatePayout_ProportionalSplit() public pure {
        // Two bettors each with half the winningPool
        // stake1 = stake2 = 50; winningPool = 100; losingPool = 40
        // payout per bettor = (50 * 40) / 100 + 50 = 20 + 50 = 70
        uint256 payout = SettlementLib.calculatePayout(50 ether, 100 ether, 40 ether);
        assertEq(payout, 70 ether);
    }

    function test_CalculatePayout_SubWeiRounding() public pure {
        // myStake=1, winningPool=3, losingPool=1: (1*1)/3 = 0 (floor) + 1 = 1
        uint256 payout = SettlementLib.calculatePayout(1, 3, 1);
        assertEq(payout, 1);
    }

    function test_CalculatePayout_RevertsOnZeroStake() public {
        vm.expectRevert(PredictionMarket__NotWinningPosition.selector);
        _wrapper.callCalculatePayout(0, 100 ether, 50 ether);
    }

    // ============ calculateRefund — unit tests ============

    function test_CalculateRefund_BothSides() public pure {
        uint256 refund = SettlementLib.calculateRefund(30 ether, 20 ether);
        assertEq(refund, 50 ether);
    }

    function test_CalculateRefund_YesOnly() public pure {
        uint256 refund = SettlementLib.calculateRefund(40 ether, 0);
        assertEq(refund, 40 ether);
    }

    function test_CalculateRefund_NoOnly() public pure {
        uint256 refund = SettlementLib.calculateRefund(0, 25 ether);
        assertEq(refund, 25 ether);
    }

    function test_CalculateRefund_RevertsOnBothZero() public {
        vm.expectRevert(PredictionMarket__NotRefundable.selector);
        _wrapper.callCalculateRefund(0, 0);
    }

    // ============ fuzz — pot conservation ============

    function testFuzz_CalculatePayout_PreservesPotConservation(uint256 stake1, uint256 stake2, uint256 losingPool)
        public
        pure
    {
        stake1 = bound(stake1, 1, 1e27);
        stake2 = bound(stake2, 1, 1e27);
        losingPool = bound(losingPool, 0, 1e27);

        uint256 winningPool = stake1 + stake2;
        // max multiplication: 1e27 * 1e27 = 1e54 < 2^256 ≈ 1.16e77 — no overflow

        uint256 payout1 = SettlementLib.calculatePayout(stake1, winningPool, losingPool);
        uint256 payout2 = SettlementLib.calculatePayout(stake2, winningPool, losingPool);

        assertLe(payout1 + payout2, winningPool + losingPool, "pot conservation violated");
    }

    // ============ fuzz — refund sum ============

    function testFuzz_CalculateRefund_SumEqualsTotalStaked(uint256 yesStake, uint256 noStake) public pure {
        yesStake = bound(yesStake, 0, 1e27);
        noStake = bound(noStake, 0, 1e27);
        vm.assume(yesStake > 0 || noStake > 0); // skip both-zero revert path (tested in unit test)

        uint256 refund = SettlementLib.calculateRefund(yesStake, noStake);
        assertEq(refund, yesStake + noStake);
    }
}
