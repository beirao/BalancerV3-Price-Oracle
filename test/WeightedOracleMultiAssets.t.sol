// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console2.sol";

import {TestTwapBal} from "./helper/TestTwapBal.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {WeightedPool} from "lib/balancer-v3-monorepo/pkg/pool-weighted/contracts/WeightedPool.sol";
import {WeightedPoolGeomeanOracleHookContract} from
    "../contracts/WeightedPoolGeomeanOracleHookContract.sol";

contract WeightedOracleMultiAssets is TestTwapBal {
    WeightedPool public pool;
    IERC20[] public assets;
    WeightedPoolGeomeanOracleHookContract public hookOracleContract;

    function setUp() public override {
        super.setUp();

        console2.log("usdt : ", address(usdt));
        console2.log("usdc : ", address(usdc));
        console2.log("weth : ", address(weth));

        IERC20[] memory assetsTemp = new IERC20[](3);
        assetsTemp[0] = usdt;
        assetsTemp[1] = usdc;
        assetsTemp[2] = weth;
        assets = sort(assetsTemp);

        address[] memory assetsSorted = new address[](assets.length);
        for (uint256 i; i < assets.length; i++) {
            assetsSorted[i] = address(assets[i]);
        }

        hookOracleContract = new WeightedPoolGeomeanOracleHookContract(
            address(vaultV3), address(weightedPoolFactory), address(referenceToken)
        );

        pool = WeightedPool(createWeightedPool(assets, address(hookOracleContract), address(this)));

        uint256[] memory amountsToAdd = new uint256[](assets.length);
        amountsToAdd[0] = 1_000_000e18; // usdc
        amountsToAdd[1] = 1_000e18; // weth
        amountsToAdd[2] = 1_000_000e18; // usdt

        vm.prank(userA);
        router.initialize(address(pool), assets, amountsToAdd);
        vm.stopPrank();
    }

    function test_priceUpdatesAfterSwaps() public {
        _performSwapsToGeneratePriceData(address(pool), hookOracleContract);

        // Get initial price
        uint256 initialPrice = hookOracleContract.getGeomeanPrice(address(usdt), 300);

        // Perform more swaps with correct decimal scaling
        _swap(address(pool), hookOracleContract, usdc, usdt, 5e18, 12); // 500 tokens
        _swap(address(pool), hookOracleContract, usdc, usdt, 3e18, 12); // 300 tokens

        // Get updated price
        uint256 updatedPrice = hookOracleContract.getGeomeanPrice(address(usdt), 300);

        assertNotEq(initialPrice, updatedPrice, "Prices should change after swaps");
    }

    function test_getGeomeanPrice1() public {
        _performSwapsToGeneratePriceData(address(pool), hookOracleContract);

        uint256 lastPrice = 0;
        for (uint256 i = 1; i < 500; i++) {
            uint256 price = hookOracleContract.getGeomeanPrice(address(usdt), i);
            console2.log("Price (%d) ::: %18e ", i, price, lastPrice >= price);
            lastPrice = price;
        }
    }

    // function test_getGeomeanPriceLinearity() public {
    //     _performSwapsToGeneratePriceData(address(pool), hookOracleContract);

    //     console2.log("---");
    //     uint256 lastPrice = hookOracleContract.getGeomeanPrice(address(usdt), 1);
    //     for (uint256 i = 2; i < 500; i++) {
    //         uint256 price = hookOracleContract.getGeomeanPrice(address(usdt), i);
    //         assertLe(price, lastPrice);
    //         lastPrice = price;
    //     }
    // }

    // function test_priceManipulation1() public {
    //     _performSwapsToGeneratePriceData(address(pool), hookOracleContract);

    //     uint256 observationPeriod = 1 hours;
    //     uint256 lastPrice = hookOracleContract.getGeomeanPrice(address(usdt), observationPeriod);

    //     // starting price: 1.254418132319424722
    //     for (uint256 i = 0; i < 500; i++) {
    //         _swapToken1ToToken2(address(pool), hookOracleContract, 10_000e18, 0); // n = 1
    //     }
    //     _updateTimestamp(24); // 24 3 block manipulation on eth mainnet

    //     assertApproxEqRel(
    //         lastPrice, hookOracleContract.getGeomeanPrice(address(usdt), observationPeriod), 0.8e18
    //     ); // less than 8%

    //     for (uint256 i = 0; i < 73; i++) {
    //         _swapToken2ToToken1(address(pool), hookOracleContract, 10_000e18, 0); // n = 1
    //     }
    //     _updateTimestamp(1 hours);

    //     assertApproxEqRel(
    //         hookOracleContract.getLastPrice(address(usdt)),
    //         hookOracleContract.getGeomeanPrice(address(usdt), observationPeriod),
    //         0.001e18
    //     ); // less than 0,001%
    // }

    // function test_priceManipulationSingleBlock() public {
    //     _performSwapsToGeneratePriceData(address(pool), hookOracleContract);

    //     uint256 lastPrice = hookOracleContract.getGeomeanPrice(address(usdt), 1 hours);

    //     for (uint256 i = 0; i < 30; i++) {
    //         _swapToken1ToToken2(address(pool), hookOracleContract, 300_000e18, 0); // n = 1
    //     }
    //     _updateTimestamp(2);

    //     // Price should be the same as the last price before manipulation
    //     assertEq(lastPrice, hookOracleContract.getGeomeanPrice(address(usdt), 1 hours));
    // }

    // function test_priceAccuracy(
    //     uint256 _amountIn,
    //     uint256 _amountOut,
    //     uint256 _skipIn,
    //     uint256 _skipOut
    // ) public {
    //     _amountIn = bound(_amountIn, 1e15, 200e18);
    //     _amountOut = bound(_amountOut, 1e15, 200e18);
    //     _skipIn = bound(_skipIn, 1, 1000);
    //     _skipOut = bound(_skipOut, 1, 1000);

    //     _performSwapsToGeneratePriceData(address(pool), hookOracleContract);

    //     _swapToken2ToToken1(address(pool), hookOracleContract, 1e18, 12);
    //     _swapToken1ToToken2(address(pool), hookOracleContract, 1e18, 12);
    //     _swapToken2ToToken1(address(pool), hookOracleContract, 1e18, 12);
    //     _swapToken1ToToken2(address(pool), hookOracleContract, 1e18, 12);
    //     _swapToken2ToToken1(address(pool), hookOracleContract, 1e18, 12);
    //     _swapToken1ToToken2(address(pool), hookOracleContract, 1e18, 12);
    //     _swapToken2ToToken1(address(pool), hookOracleContract, 1e18, 12);
    //     _swapToken1ToToken2(address(pool), hookOracleContract, 5e18, 5);
    //     _swapToken2ToToken1(address(pool), hookOracleContract, 10e18, 24);
    //     _swapToken1ToToken2(address(pool), hookOracleContract, 15e18, 36);
    //     _swapToken2ToToken1(address(pool), hookOracleContract, 20e18, 12);
    //     _swapToken1ToToken2(address(pool), hookOracleContract, 25e18, 48);
    //     _swapToken2ToToken1(address(pool), hookOracleContract, 30e18, 60);
    //     _swapToken1ToToken2(address(pool), hookOracleContract, 35e18, 3);
    //     _swapToken2ToToken1(address(pool), hookOracleContract, 40e18, 72);
    //     _swapToken1ToToken2(address(pool), hookOracleContract, 45e18, 6);
    //     _swapToken2ToToken1(address(pool), hookOracleContract, 50e18, 18);
    //     _swapToken1ToToken2(address(pool), hookOracleContract, 55e18, 30);
    //     _swapToken2ToToken1(address(pool), hookOracleContract, 60e18, 42);
    //     _swapToken1ToToken2(address(pool), hookOracleContract, 65e18, 54);
    //     _swapToken2ToToken1(address(pool), hookOracleContract, 70e18, 66);

    //     _swapToken2ToToken1(address(pool), hookOracleContract, _amountIn, _skipIn);
    //     _swapToken2ToToken1(address(pool), hookOracleContract, _amountOut, _skipIn);
    // }
}
