// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {TestTwapBal} from "./helper/TestTwapBal.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {WeightedPool} from "lib/balancer-v3-monorepo/pkg/pool-weighted/contracts/WeightedPool.sol";

contract WeightedOracle is TestTwapBal {
    WeightedPool public pool;
    IERC20[] public assets;

    function setUp() public override {
        super.setUp();
        vm.selectFork(forkIdEth);

        IERC20[] memory assetsTemp = new IERC20[](2);
        assetsTemp[0] = usdt;
        assetsTemp[1] = usdc;

        assets = sort(assetsTemp);

        pool = WeightedPool(createWeightedPool(assets, address(0), address(this)));

        uint256[] memory amountsToAdd = new uint256[](assets.length);
        amountsToAdd[0] = 1_000_000e18;
        amountsToAdd[1] = 1_000_000e18;

        vm.prank(userA);
        router.initialize(address(pool), assets, amountsToAdd);
        vm.stopPrank();
    }

    function test_Increment() public {
        assertNotEq(address(pool), address(0));
    }

    function test_easySwap() public {
        uint256 amount = 1000000000000000000;
        usdt.transfer(address(pool), amount);
        usdt.approve(address(pool), amount);

        router.swapExactTokensForTokens(amount, 0, assets, address(this));
    }
}
