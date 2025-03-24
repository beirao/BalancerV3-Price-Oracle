// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console2.sol";

import {TestTwapBal} from "./helper/TestTwapBal.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {WeightedPool} from "lib/balancer-v3-monorepo/pkg/pool-weighted/contracts/WeightedPool.sol";
import {WeightedPoolGeomeanOracleHookContract} from
    "../contracts/WeightedPoolGeomeanOracleHookContract.sol";

contract WeightedOracle is TestTwapBal {
    WeightedPool public pool;
    IERC20[] public assets;
    WeightedPoolGeomeanOracleHookContract public hookOracleContract;

    function setUp() public override {
        super.setUp();
        vm.selectFork(forkIdEth);

        IERC20[] memory assetsTemp = new IERC20[](2);
        assetsTemp[0] = usdt;
        assetsTemp[1] = usdc;

        assets = sort(assetsTemp);

        address[] memory assetsSorted = new address[](assets.length);
        for (uint256 i; i < assets.length; i++) {
            assetsSorted[i] = address(assets[i]);
        }

        hookOracleContract = new WeightedPoolGeomeanOracleHookContract(
            address(vaultV3), address(weightedPoolFactory), address(usdc)
        );

        pool = WeightedPool(createWeightedPool(assets, address(hookOracleContract), address(this)));

        uint256[] memory amountsToAdd = new uint256[](assets.length);
        amountsToAdd[0] = 1_000_000e18;
        amountsToAdd[1] = 1_000_000e18;

        vm.prank(userA);
        router.initialize(address(pool), assets, amountsToAdd);
        vm.stopPrank();
    }

    function test_Increment() public view {
        assertNotEq(address(pool), address(0));
    }

    function test_easySwap(uint256 amount) public {
        amount = bound(amount, 1e18, 10_000e18);
        _easySwap(amount, 100);
    }

    function test_getPrice() public {
        _easySwap(10_000e18, 100);
        console2.log("Price (oracle) ::: %18e", hookOracleContract.getLastPrice(address(usdt)));

        _easySwap(1e18, 100);
        console2.log("Price (oracle) ::: %18e", hookOracleContract.getLastPrice(address(usdt)));
        _easySwap(1e18, 100);
        console2.log("Price (oracle) ::: %18e", hookOracleContract.getLastPrice(address(usdt)));
    }

    function test_getGeomeanPrice1() public {
        _easySwap(10_000e18, 100); // n = 1
        _easySwap(1e18, 100); // n = 2
        _easySwap(10_000e18, 100); // n = 3
        _easySwap(1e18, 100); // n = 4
        _easySwap(1e10, 100); // n = 5
        _easySwap(100000e18, 100); // n = 5
        _easySwap(1e18, 5); // n = 5
        _easySwap(1e18, 1); // n = 5
        _easySwap(1e18, 1); // n = 5
        _easySwap(1e18, 100); // n = 4
        // vm.warp(block.timestamp + 50);

        console2.log("---");
        // uint256 lastPrice = 0;
        // for (uint256 i = 1; i < 500; i++) {
        //     uint256 price = hookOracleContract.getGeomeanPrice(address(usdt), i);
        //     console2.log("Price (%d) ::: %18e ", i, price, lastPrice >= price);
        //     lastPrice = price;
        // }
        console2.log(
            "Price (%d) ::: %18e", 102, hookOracleContract.getGeomeanPrice(address(usdt), 102)
        );
        console2.log(
            "Price (%d) ::: %18e", 103, hookOracleContract.getGeomeanPrice(address(usdt), 103)
        );
        console2.log("---");

        // _easySwap(1e10, 100); // n = 4
    }

    function test_getGeomeanPriceLinearity() public {
        _easySwap(10_000e18, 100); // n = 1
        _easySwap(1e18, 100); // n = 2
        _easySwap(10_000e18, 100); // n = 3
        _easySwap(1e18, 100); // n = 4
        _easySwap(1e10, 100); // n = 5
        _easySwap(100000e18, 100); // n = 5
        _easySwap(1e18, 5); // n = 5
        _easySwap(1e18, 1); // n = 5
        _easySwap(1e18, 1); // n = 5
        _easySwap(1e18, 100); // n = 4

        console2.log("---");
        uint256 lastPrice = hookOracleContract.getGeomeanPrice(address(usdt), 1);
        for (uint256 i = 2; i < 500; i++) {
            uint256 price = hookOracleContract.getGeomeanPrice(address(usdt), i);
            assertLe(price, lastPrice);
            lastPrice = price;
        }
    }
    /// -------- Helpers --------- ///

    function _easySwap(uint256 amount, uint256 skip) public {
        vm.warp(block.timestamp / 12 * 12 + skip);
        vm.roll(block.timestamp / 12);
        // Get initial balances
        uint256 initialUsdtBalance = usdt.balanceOf(address(userC));
        uint256 initialUsdcBalance = usdc.balanceOf(address(userC));

        // Approve tokens for the router
        usdt.approve(address(router), amount);

        // Perform swap using TRouter's swapSingleTokenExactIn function
        vm.startPrank(userC);
        router.swapSingleTokenExactIn(
            address(pool),
            usdt,
            usdc,
            amount,
            0 // No minimum amount out requirement for test
        );
        vm.stopPrank();

        // Check balances after swap
        uint256 finalUsdtBalance = usdt.balanceOf(address(userC));
        uint256 finalUsdcBalance = usdc.balanceOf(address(userC));

        // Verify swap was successful
        assertEq(
            initialUsdtBalance - finalUsdtBalance, amount, "USDT amount not deducted correctly"
        );
        assertTrue(finalUsdcBalance > initialUsdcBalance, "USDC balance did not increase");

        console2.log("");
        console2.log(
            "Price (in/out) ::: %18e", amount * 1e18 / (finalUsdcBalance - initialUsdcBalance)
        );
    }
}
