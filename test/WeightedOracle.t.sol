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
            address(vaultV3), address(weightedPoolFactory), address(referenceToken)
        );

        pool = WeightedPool(createWeightedPool(assets, address(hookOracleContract), address(this)));

        uint256[] memory amountsToAdd = new uint256[](assets.length);
        amountsToAdd[0] = 1_000_000e18;
        amountsToAdd[1] = 1_000_000e18;

        vm.prank(userA);
        router.initialize(address(pool), assets, amountsToAdd);
        vm.stopPrank();
    }

    function test_priceUpdatesAfterSwaps() public {
        _performSwapsToGeneratePriceData(address(pool), hookOracleContract);

        // Get initial price
        uint256 initialPrice = hookOracleContract.getGeomeanPrice(address(usdt), 300);

        // Perform more swaps with correct decimal scaling
        _swap(address(pool), hookOracleContract, usdc, usdt, 500e18, 12); // 500 tokens
        _swap(address(pool), hookOracleContract, usdc, usdt, 300e18, 12); // 300 tokens

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

    function test_getGeomeanPriceLinearity() public {
        _performSwapsToGeneratePriceData(address(pool), hookOracleContract);

        console2.log("---");
        uint256 lastPrice = hookOracleContract.getGeomeanPrice(address(usdt), 1);
        for (uint256 i = 2; i < 500; i++) {
            uint256 price = hookOracleContract.getGeomeanPrice(address(usdt), i);
            assertLe(price, lastPrice);
            lastPrice = price;
        }
    }

    function test_priceManipulation1() public {
        _performSwapsToGeneratePriceData(address(pool), hookOracleContract);

        uint256 observationPeriod = 1 hours;
        uint256 lastPrice = hookOracleContract.getGeomeanPrice(address(usdt), observationPeriod);

        // starting price: 1.254418132319424722
        for (uint256 i = 0; i < 500; i++) {
            _swap(address(pool), hookOracleContract, usdt, usdc, 10_000e18, 0); // n = 1
        }
        _updateTimestamp(24); // 24 3 block manipulation on eth mainnet

        assertApproxEqRel(
            lastPrice, hookOracleContract.getGeomeanPrice(address(usdt), observationPeriod), 0.8e18
        ); // less than 8%

        for (uint256 i = 0; i < 73; i++) {
            _swap(address(pool), hookOracleContract, usdc, usdt, 10_000e18, 0); // n = 1
        }
        _updateTimestamp(1 hours);

        assertApproxEqRel(
            hookOracleContract.getLastPrice(address(usdt)),
            hookOracleContract.getGeomeanPrice(address(usdt), observationPeriod),
            0.001e18
        ); // less than 0,001%
    }

    function test_priceManipulationSingleBlock() public {
        _performSwapsToGeneratePriceData(address(pool), hookOracleContract);

        uint256 lastPrice = hookOracleContract.getGeomeanPrice(address(usdt), 1 hours);

        for (uint256 i = 0; i < 30; i++) {
            _swap(address(pool), hookOracleContract, usdt, usdc, 300_000e18, 0); // n = 1
        }
        _updateTimestamp(2);

        // Price should be the same as the last price before manipulation
        assertEq(lastPrice, hookOracleContract.getGeomeanPrice(address(usdt), 1 hours));
    }

    function test_priceAccuracy(
        uint256 _amountIn,
        uint256 _amountOut,
        uint256 _skipIn,
        uint256 _skipOut
    ) public {
        _amountIn = bound(_amountIn, 1e15, 200e18);
        _amountOut = bound(_amountOut, 1e15, 200e18);
        _skipIn = bound(_skipIn, 1, 1000);
        _skipOut = bound(_skipOut, 1, 1000);

        _performSwapsToGeneratePriceData(address(pool), hookOracleContract);

        _swap(address(pool), hookOracleContract, usdc, usdt, 1e18, 12);
        _swap(address(pool), hookOracleContract, usdt, usdc, 1e18, 12);
        _swap(address(pool), hookOracleContract, usdc, usdt, 1e18, 12);
        _swap(address(pool), hookOracleContract, usdt, usdc, 1e18, 12);
        _swap(address(pool), hookOracleContract, usdc, usdt, 1e18, 12);
        _swap(address(pool), hookOracleContract, usdt, usdc, 1e18, 12);
        _swap(address(pool), hookOracleContract, usdc, usdt, 1e18, 12);
        _swap(address(pool), hookOracleContract, usdt, usdc, 5e18, 5);
        _swap(address(pool), hookOracleContract, usdc, usdt, 10e18, 24);
        _swap(address(pool), hookOracleContract, usdt, usdc, 15e18, 36);
        _swap(address(pool), hookOracleContract, usdc, usdt, 20e18, 12);
        _swap(address(pool), hookOracleContract, usdt, usdc, 25e18, 48);
        _swap(address(pool), hookOracleContract, usdc, usdt, 30e18, 60);
        _swap(address(pool), hookOracleContract, usdt, usdc, 35e18, 3);
        _swap(address(pool), hookOracleContract, usdc, usdt, 40e18, 72);
        _swap(address(pool), hookOracleContract, usdt, usdc, 45e18, 6);
        _swap(address(pool), hookOracleContract, usdc, usdt, 50e18, 18);
        _swap(address(pool), hookOracleContract, usdt, usdc, 55e18, 30);
        _swap(address(pool), hookOracleContract, usdc, usdt, 60e18, 42);
        _swap(address(pool), hookOracleContract, usdt, usdc, 65e18, 54);
        _swap(address(pool), hookOracleContract, usdc, usdt, 70e18, 66);

        _swap(address(pool), hookOracleContract, usdc, usdt, _amountIn, _skipIn);
        _swap(address(pool), hookOracleContract, usdt, usdc, _amountOut, _skipOut);
    }
}
