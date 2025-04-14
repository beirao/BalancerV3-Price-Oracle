// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console2.sol";

import {TestTwapBal} from "../helper/TestTwapBal.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {WeightedPool} from "lib/balancer-v3-monorepo/pkg/pool-weighted/contracts/WeightedPool.sol";
import {WeightedPoolGeomeanOracleHookContract} from
    "../../contracts/WeightedPoolGeomeanOracleHookContract.sol";

contract WeightedOracleMultiAssetsTest is TestTwapBal {
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

        hookOracleContract =
            new WeightedPoolGeomeanOracleHookContract(address(vaultV3), address(referenceToken));

        uint256[] memory normalizedWeights = new uint256[](assets.length);
        normalizedWeights[0] = 5e17;
        normalizedWeights[1] = 25e16;
        normalizedWeights[2] = 25e16;

        pool = WeightedPool(
            createWeightedPool(
                assets, normalizedWeights, address(hookOracleContract), address(this)
            )
        );

        uint256[] memory amountsToAdd = new uint256[](assets.length);
        amountsToAdd[0] = 1_000_000e18; // usdc
        amountsToAdd[1] = 100_000e18; // weth
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

    function test_getGeomeanPriceLinearity() public {
        _performSwapsToGeneratePriceData(address(pool), hookOracleContract);

        uint256 lastPrice = hookOracleContract.getGeomeanPrice(address(usdt), 1);
        for (uint256 i = 2; i < 500; i++) {
            uint256 price = hookOracleContract.getGeomeanPrice(address(usdt), i);
            // console2.log("Price (%d) ::: %18e ", i, price, lastPrice <= price);
            assertGe(price, lastPrice);
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
            console2.log(
                "lastPrice ::: %18e",
                hookOracleContract.getGeomeanPrice(address(usdt), observationPeriod)
            );
        }

        for (uint256 i = 0; i < 5; i++) {
            _swap(address(pool), hookOracleContract, usdt, usdc, 1e17, 12); // n = 1
        }

        assertApproxEqRel(
            lastPrice, hookOracleContract.getGeomeanPrice(address(usdt), observationPeriod), 0.1e18
        ); // less than 8%

        for (uint256 i = 0; i < 62; i++) {
            _swap(address(pool), hookOracleContract, usdc, usdt, 10_000e18, 0); // n = 1
        }

        for (uint256 i = 0; i < 1 hours / 12; i++) {
            _swap(address(pool), hookOracleContract, usdt, usdc, 1e17, 12); // n = 1
        }

        assertApproxEqRel(
            hookOracleContract.getLastPrice(address(usdt)),
            hookOracleContract.getGeomeanPrice(address(usdt), observationPeriod),
            0.01e18
        ); // less than 1%
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

    function test_priceManipulation16Blocks() public {
        _performSwapsToGeneratePriceData(address(pool), hookOracleContract);

        _swap(address(pool), hookOracleContract, usdc, usdt, 1e18, 1 hours);

        uint256 observationPeriod = 1 hours;
        uint256 lastGeomeanPrice =
            hookOracleContract.getGeomeanPrice(address(usdt), observationPeriod);

        console2.log("---");
        console2.log("lastPrice        ::: %18e", hookOracleContract.getLastPrice(address(usdt)));
        console2.log(
            "getGeomeanPrice  ::: %18e",
            hookOracleContract.getGeomeanPrice(address(usdt), observationPeriod)
        );
        uint256 balanceUstBefore = usdt.balanceOf(address(userC));
        uint256 balanceUsdcBefore = usdc.balanceOf(address(userC));
        console2.log("balance usdt ::: %18e", balanceUstBefore);
        console2.log("balance usdc ::: %18e", balanceUsdcBefore);

        // FL manipulation
        for (uint256 i = 0; i < 30; i++) {
            _swap(address(pool), hookOracleContract, usdc, usdt, 100_000e18, 0);
        }

        // 16 block manipulation
        uint256 blockManipulationNumber = 16;
        for (uint256 i = 0; i < blockManipulationNumber; i++) {
            // console2.log("lastPrice  1      ::: %18e", hookOracleContract.getLastPrice(address(usdt)));
            _updateTimestamp(12);
            _swap(address(pool), hookOracleContract, usdt, usdc, 1e17, 0);
        }

        console2.log("---");
        console2.log("lastPrice        ::: %18e", hookOracleContract.getLastPrice(address(usdt)));
        console2.log(
            "getGeomeanPrice  ::: %18e",
            hookOracleContract.getGeomeanPrice(address(usdt), observationPeriod)
        );

        // Back to original price
        for (uint256 i = 0; i < 106; i++) {
            _swap(address(pool), hookOracleContract, usdt, usdc, 10_000e18, 0);
        }
        _swap(address(pool), hookOracleContract, usdt, usdc, 1000e18, 0);
        _swap(address(pool), hookOracleContract, usdt, usdc, 1000e18, 0);

        // Update price back to normal
        for (uint256 i = 0; i < blockManipulationNumber + 10; i++) {
            // console2.log("lastPrice  2      ::: %18e", hookOracleContract.getLastPrice(address(usdt)));
            _updateTimestamp(12);
            _swap(address(pool), hookOracleContract, usdt, usdc, 1e15, 0);
        }
        _swap(address(pool), hookOracleContract, usdc, usdt, 2597e18, 0);

        console2.log("---");
        console2.log("lastPrice        ::: %18e", hookOracleContract.getLastPrice(address(usdt)));
        console2.log(
            "getGeomeanPrice  ::: %18e",
            hookOracleContract.getGeomeanPrice(address(usdt), observationPeriod)
        );
        uint256 balanceUstAfter = usdt.balanceOf(address(userC));
        uint256 balanceUsdcAfter = usdc.balanceOf(address(userC));
        console2.log("balance usdt ::: %18e", int256(balanceUstAfter) - int256(balanceUstBefore));
        console2.log("balance usdc ::: %18e", int256(balanceUsdcAfter) - int256(balanceUsdcBefore));

        assertApproxEqRel(
            lastGeomeanPrice,
            hookOracleContract.getGeomeanPrice(address(usdt), observationPeriod),
            0.04e18
        );
    }

    function test_priceManipulation5Blocks() public {
        _performSwapsToGeneratePriceData(address(pool), hookOracleContract);

        _swap(address(pool), hookOracleContract, usdc, usdt, 1e18, 1 hours);

        uint256 observationPeriod = 1 hours;
        uint256 lastGeomeanPrice =
            hookOracleContract.getGeomeanPrice(address(usdt), observationPeriod);

        console2.log("---");
        console2.log("lastPrice        ::: %18e", hookOracleContract.getLastPrice(address(usdt)));
        console2.log(
            "getGeomeanPrice  ::: %18e",
            hookOracleContract.getGeomeanPrice(address(usdt), observationPeriod)
        );
        uint256 balanceUstBefore = usdt.balanceOf(address(userC));
        uint256 balanceUsdcBefore = usdc.balanceOf(address(userC));
        console2.log("balance usdt ::: %18e", balanceUstBefore);
        console2.log("balance usdc ::: %18e", balanceUsdcBefore);

        // FL manipulation
        for (uint256 i = 0; i < 30; i++) {
            _swap(address(pool), hookOracleContract, usdc, usdt, 100_000e18, 0);
        }

        // 16 block manipulation
        uint256 blockManipulationNumber = 5;
        for (uint256 i = 0; i < blockManipulationNumber; i++) {
            // console2.log("lastPrice  1      ::: %18e", hookOracleContract.getLastPrice(address(usdt)));
            _updateTimestamp(12);
            _swap(address(pool), hookOracleContract, usdt, usdc, 1e17, 0);
        }

        console2.log("---");
        console2.log("lastPrice        ::: %18e", hookOracleContract.getLastPrice(address(usdt)));
        console2.log(
            "getGeomeanPrice  ::: %18e",
            hookOracleContract.getGeomeanPrice(address(usdt), observationPeriod)
        );

        // Back to original price
        for (uint256 i = 0; i < 106; i++) {
            _swap(address(pool), hookOracleContract, usdt, usdc, 10_000e18, 0);
        }
        _swap(address(pool), hookOracleContract, usdt, usdc, 1000e18, 0);
        _swap(address(pool), hookOracleContract, usdt, usdc, 1000e18, 0);

        // Update price back to normal
        for (uint256 i = 0; i < blockManipulationNumber + 10; i++) {
            // console2.log("lastPrice  2      ::: %18e", hookOracleContract.getLastPrice(address(usdt)));
            _updateTimestamp(12);
            _swap(address(pool), hookOracleContract, usdt, usdc, 1e15, 0);
        }
        _swap(address(pool), hookOracleContract, usdc, usdt, 2597e18, 0);

        console2.log("---");
        console2.log("lastPrice        ::: %18e", hookOracleContract.getLastPrice(address(usdt)));
        console2.log(
            "getGeomeanPrice  ::: %18e",
            hookOracleContract.getGeomeanPrice(address(usdt), observationPeriod)
        );
        uint256 balanceUstAfter = usdt.balanceOf(address(userC));
        uint256 balanceUsdcAfter = usdc.balanceOf(address(userC));
        console2.log("balance usdt ::: %18e", int256(balanceUstAfter) - int256(balanceUstBefore));
        console2.log("balance usdc ::: %18e", int256(balanceUsdcAfter) - int256(balanceUsdcBefore));

        assertApproxEqRel(
            lastGeomeanPrice,
            hookOracleContract.getGeomeanPrice(address(usdt), observationPeriod),
            0.01e18
        );
    }

    function test_priceAccuracyWeth() public {
        _performSwapsToGeneratePriceData(address(pool), hookOracleContract);
        // Create swap history between all pairs to establish price relationships
        _swap(address(pool), hookOracleContract, weth, usdt, 1e18, 12);
        _swap(address(pool), hookOracleContract, usdt, weth, 1500e18, 12);
        _swap(address(pool), hookOracleContract, usdc, weth, 1500e18, 12);
        _swap(address(pool), hookOracleContract, weth, usdc, 1e18, 12);
        _swap(address(pool), hookOracleContract, usdt, usdc, 10e18, 1 minutes);
        _swap(address(pool), hookOracleContract, usdc, usdt, 10e18, 12 minutes);
        _swap(address(pool), hookOracleContract, weth, usdt, 2e18, 24);
        _swap(address(pool), hookOracleContract, usdc, weth, 3000e18, 24);
        _swap(address(pool), hookOracleContract, usdt, usdc, 20e18, 24);

        uint256 lastPriceWeth = hookOracleContract.getLastPrice(address(weth));
        uint256 lastPriceUsdt = hookOracleContract.getLastPrice(address(usdt));

        console2.log("weth price lastPrice ::: %18e", lastPriceWeth);
        console2.log("usdt price lastPrice ::: %18e", lastPriceUsdt);

        _swap(address(pool), hookOracleContract, weth, usdt, 1e18, 12);

        console2.log(
            "weth price lastPrice ::: %18e", hookOracleContract.getLastPrice(address(weth))
        );
        console2.log(
            "usdt price lastPrice ::: %18e", hookOracleContract.getLastPrice(address(usdt))
        );

        assertGt(lastPriceWeth, hookOracleContract.getLastPrice(address(weth)));
        assertLt(lastPriceUsdt, hookOracleContract.getLastPrice(address(usdt)));

        uint256 balanceWeth = weth.balanceOf(address(userC));
        uint256 balanceUsdc = usdc.balanceOf(address(userC));

        _swap(address(pool), hookOracleContract, weth, usdc, 1e18, 12);

        console2.log("usdc price lastPrice ::: %18e", balanceWeth);
        console2.log(
            "hookOracleContract.getLastPrice(address(weth)) ::: %18e",
            hookOracleContract.getLastPrice(address(weth))
        );

        assertApproxEqRel(
            usdc.balanceOf(address(userC)) - balanceUsdc,
            hookOracleContract.getLastPrice(address(weth)),
            0.001e18
        );

        // console2.log("weth price getGeomeanPrice ::: ", hookOracleContract.getGeomeanPrice(address(weth), 300));
        // console2.log("usdt price getGeomeanPrice ::: ", hookOracleContract.getGeomeanPrice(address(usdt), 300));
    }

    function test_priceAccuracyMultiAssets(
        uint256 _amount1,
        uint256 _amount2,
        uint256 _amount3,
        uint256 _skip1,
        uint256 _skip2,
        uint256 _skip3
    ) public {
        _amount1 = bound(_amount1, 1e15, 200e18);
        _amount2 = bound(_amount2, 1e15, 200e18);
        _amount3 = bound(_amount3, 1e15, 200e18);
        _skip1 = bound(_skip1, 1, 1000);
        _skip2 = bound(_skip2, 1, 1000);
        _skip3 = bound(_skip3, 1, 1000);
        _performSwapsToGeneratePriceData(address(pool), hookOracleContract);

        _swap(address(pool), hookOracleContract, usdt, usdc, 45e18, 6);
        _swap(address(pool), hookOracleContract, usdc, usdt, 40e18, 72);
        _swap(address(pool), hookOracleContract, weth, usdt, 0.3e18, 3);
        _swap(address(pool), hookOracleContract, usdt, weth, 1500e18, 12);
        _swap(address(pool), hookOracleContract, usdc, weth, 3000e18, 18);
        _swap(address(pool), hookOracleContract, usdt, usdc, 15e18, 36);
        _swap(address(pool), hookOracleContract, usdc, usdt, 70e18, 66);
        _swap(address(pool), hookOracleContract, weth, usdc, 1.5e18, 6);
        _swap(address(pool), hookOracleContract, usdt, usdc, 55e18, 30);
        _swap(address(pool), hookOracleContract, usdc, usdt, 1e18, 12);
        _swap(address(pool), hookOracleContract, usdt, usdc, 1e18, 12);
        _swap(address(pool), hookOracleContract, usdc, usdt, 30e18, 60);
        _swap(address(pool), hookOracleContract, usdt, usdc, 65e18, 54);
        _swap(address(pool), hookOracleContract, weth, usdc, 0.5e18, 12);
        _swap(address(pool), hookOracleContract, usdc, usdt, 20e18, 12);
        _swap(address(pool), hookOracleContract, usdt, usdc, 35e18, 3);
        _swap(address(pool), hookOracleContract, usdc, usdt, 10e18, 24);
        _swap(address(pool), hookOracleContract, weth, usdt, 0.8e18, 36);
        _swap(address(pool), hookOracleContract, usdc, usdt, 1e18, 12);
        _swap(address(pool), hookOracleContract, usdt, usdc, 5e18, 5);
        _swap(address(pool), hookOracleContract, usdc, usdt, 50e18, 18);
        _swap(address(pool), hookOracleContract, usdt, usdc, 25e18, 48);
        _swap(address(pool), hookOracleContract, usdc, weth, 1000e18, 24);
        _swap(address(pool), hookOracleContract, usdt, weth, 800e18, 72);
        _swap(address(pool), hookOracleContract, weth, usdc, 1.2e18, 48);
        _swap(address(pool), hookOracleContract, usdc, usdt, 1e18, 12);
        _swap(address(pool), hookOracleContract, usdt, usdc, 1e18, 12);
        _swap(address(pool), hookOracleContract, usdc, usdt, 60e18, 42);
        _swap(address(pool), hookOracleContract, usdc, weth, 2000e18, 60);
        _swap(address(pool), hookOracleContract, usdc, usdt, 1e18, 12);

        _swap(address(pool), hookOracleContract, usdc, usdt, _amount1, _skip1);
        _swap(address(pool), hookOracleContract, usdt, weth, _amount2, _skip2);
        _swap(address(pool), hookOracleContract, weth, usdc, _amount3, _skip3);
    }

    function _performSwapsToGeneratePriceData(
        address _pool,
        WeightedPoolGeomeanOracleHookContract _hookOracleContract
    ) internal {
        _swap(_pool, _hookOracleContract, usdt, usdc, 10_000e18, 10 minutes);
        _swap(_pool, _hookOracleContract, usdt, usdc, 1e18, 10 minutes);
        _swap(_pool, _hookOracleContract, usdt, usdc, 10_000e18, 10 minutes);
        _swap(_pool, _hookOracleContract, usdt, usdc, 1e18, 50 minutes);
        _swap(_pool, _hookOracleContract, usdt, usdc, 1e18, 5 minutes);
        _swap(_pool, _hookOracleContract, usdt, usdc, 1e18, 10 minutes);
        _swap(_pool, _hookOracleContract, usdt, usdc, 1e15, 2 minutes);
        _swap(_pool, _hookOracleContract, usdt, usdc, 100000e18, 1 minutes);
        _swap(_pool, _hookOracleContract, usdt, usdc, 1e18, 5);
        _swap(_pool, _hookOracleContract, usdt, usdc, 1e18, 1);
        _swap(_pool, _hookOracleContract, usdt, usdc, 1e18, 1);
        _swap(_pool, _hookOracleContract, usdt, usdc, 1e18, 1 minutes);
    }
}
