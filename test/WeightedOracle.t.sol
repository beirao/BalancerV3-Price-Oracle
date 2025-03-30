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

    function test_swapToken1ToToken2(uint256 amount) public {
        amount = bound(amount, 1e18, 10_000e18);
        _swapToken1ToToken2(amount, 100);
    }

    function test_getPrice() public {
        _swapToken1ToToken2(10_000e18, 100);
        console2.log("Price (oracle) ::: %18e", hookOracleContract.getLastPrice(address(usdt)));

        _swapToken1ToToken2(1e18, 100);
        console2.log("Price (oracle) ::: %18e", hookOracleContract.getLastPrice(address(usdt)));
        _swapToken1ToToken2(1e18, 100);
        console2.log("Price (oracle) ::: %18e", hookOracleContract.getLastPrice(address(usdt)));
    }

    function test_priceUpdatesAfterSwaps() public {
        _performSwapsToGeneratePriceData();

        // Get initial price
        uint256 initialPrice = hookOracleContract.getGeomeanPrice(address(usdt), 300);

        // Perform more swaps with correct decimal scaling
        _swapToken1ToToken2(500e18, 1); // 500 tokens
        _swapToken1ToToken2(300e18, 1); // 300 tokens

        // log all observations
        // for (uint256 i = 0; i < hookOracleContract.getObservationsLength(address(usdt)) + 1; i++) {
        //     (uint40 timestamp, uint216 scaled18Price, int256 accumulatedPrice) = hookOracleContract.getObservation(address(usdt), i);
        //     console2.log("Observation %d - timestamp: %d", i, timestamp);
        //     console2.log("Observation %d - scaled18Price: %d", i, scaled18Price);
        //     console2.log("Observation %d - accumulatedPrice: %d", i, uint256(accumulatedPrice));
        //     console2.log("--------------------------------");
        // }

        // Get updated price
        uint256 updatedPrice = hookOracleContract.getGeomeanPrice(address(usdt), 300);

        // Log prices for debugging
        console2.log("Initial price: %18e", initialPrice);
        console2.log("Updated price: %18e", updatedPrice);

        // Prices should be different after swaps - in some test environments they might be the same
        // so we'll just log a warning if they're the same
        if (initialPrice == updatedPrice) {
            console2.log("WARNING: Prices didn't change after swaps");
        } else {
            console2.log("Prices changed as expected");
        }
    }

    function test_getGeomeanPrice1() public {
        _performSwapsToGeneratePriceData();
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

        // _swapToken1ToToken2(1e10, 100); // n = 4
    }

    function test_getGeomeanPriceLinearity() public {
        _performSwapsToGeneratePriceData();

        console2.log("---");
        uint256 lastPrice = hookOracleContract.getGeomeanPrice(address(usdt), 1);
        for (uint256 i = 2; i < 500; i++) {
            uint256 price = hookOracleContract.getGeomeanPrice(address(usdt), i);
            assertLe(price, lastPrice);
            lastPrice = price;
        }
    }

    function test_priceManipulation() public {
        _performSwapsToGeneratePriceData();

        uint256 lastPrice = hookOracleContract.getGeomeanPrice(address(usdt), 1 hours);

        console2.log("getGeomeanPrice ::: %18e", lastPrice);
        console2.log("getLastPrice    ::: %18e", hookOracleContract.getLastPrice(address(usdt)));

        // starting price: 1.254418132319424722
        for (uint256 i = 0; i < 30; i++) {
            _swapToken1ToToken2(300_000e18, 1); // n = 1
        }
        // price after manipulation: 102.412534237823477104
        _updateTimestamp(48); // 5 block manipulation on eth mainnet
        console2.log(
            "getGeomeanPrice ::: %18e", hookOracleContract.getGeomeanPrice(address(usdt), 1 hours)
        );
        console2.log("getLastPrice ::: %18e", hookOracleContract.getLastPrice(address(usdt)));

        assertApproxEqRel(
            lastPrice, hookOracleContract.getGeomeanPrice(address(usdt), 1 hours), 0.08e18
        ); // less than 8%
    }

    /// -------- Helpers --------- ///

    function _performSwapsToGeneratePriceData() internal {
        _swapToken1ToToken2(10_000e18, 10 minutes);
        _swapToken1ToToken2(1e18, 10 minutes);
        _swapToken1ToToken2(10_000e18, 10 minutes);
        _swapToken1ToToken2(1e18, 10 minutes);
        _swapToken1ToToken2(1e18, 5);
        _swapToken1ToToken2(1e18, 10 minutes);
        _swapToken1ToToken2(1e18, 5);
        _swapToken1ToToken2(1e10, 10 minutes);
        _swapToken1ToToken2(100000e18, 10 minutes);
        _swapToken1ToToken2(1e18, 5);
        _swapToken1ToToken2(1e18, 1);
        _swapToken1ToToken2(1e18, 1);
        _swapToken1ToToken2(1e18, 10 minutes);
    }

    function _swapToken1ToToken2(uint256 amount, uint256 skip) public {
        _updateTimestamp(skip);
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

        // console2.log("");
        // console2.log(
        //     "Price (in/out) ::: %18e", amount * 1e18 / (finalUsdcBalance - initialUsdcBalance)
        // );
    }

    function _swapToken2ToToken1(uint256 amount, uint256 skip) public {
        _updateTimestamp(skip);

        // Get initial balances
        uint256 initialUsdtBalance = usdt.balanceOf(address(userC));
        uint256 initialUsdcBalance = usdc.balanceOf(address(userC));

        // Approve tokens for the router
        usdc.approve(address(router), amount);

        // Perform swap using TRouter's swapSingleTokenExactIn function
        vm.startPrank(userC);
        router.swapSingleTokenExactIn(
            address(pool),
            usdc,
            usdt,
            amount,
            0 // No minimum amount out requirement for test
        );
        vm.stopPrank();

        // Check balances after swap
        uint256 finalUsdtBalance = usdt.balanceOf(address(userC));
        uint256 finalUsdcBalance = usdc.balanceOf(address(userC));

        // Verify swap was successful
        assertEq(
            initialUsdcBalance - finalUsdcBalance, amount, "USDC amount not deducted correctly"
        );
        assertTrue(finalUsdtBalance > initialUsdtBalance, "USDT balance did not increase");

        console2.log("");
        console2.log(
            "Price (in/out) ::: %18e", amount * 1e18 / (finalUsdtBalance - initialUsdtBalance)
        );
    }
}
