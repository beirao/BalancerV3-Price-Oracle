// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Counter} from "../contracts/Counter.sol";
import {TestTwapBal} from "./helper/TestTwapBal.sol";

contract WeightedOracle is TestTwapBal {
    Counter public counter;

    function setUp() public override {
        super.setUp();
        counter = new Counter();
        counter.setNumber(0);
    }

    function test_Increment() public {
        counter.increment();
        assertEq(counter.number(), 1);
    }
    
}
