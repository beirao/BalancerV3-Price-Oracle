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
            address(vaultV3), address(weightedPoolFactory), assetsSorted, address(usdc)
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
        _easySwap(amount);
    }

    function test_getPrice() public {
        _easySwap(10_000e18);
        console2.log("Price (oracle) ::: %18e", hookOracleContract.getPrice(address(usdt)));

        _easySwap(1e18);
        skip(100);
        console2.log("Price (oracle) ::: %18e", hookOracleContract.getPrice(address(usdt)));
        _easySwap(1e18);
        skip(100);
        console2.log("Price (oracle) ::: %18e", hookOracleContract.getPrice(address(usdt)));
    }

    function test_getGeomeanPrice() public {
        _easySwap(10_000e18);
        // console2.log("Price (oracle) ::: %18e", hookOracleContract.getGeomeanPrice(address(usdt)));

        _easySwap(1e18);

        _easySwap(10_000e18);

        _easySwap(1e18);

        // console2.log("Price (oracle) ::: %18e", hookOracleContract.getGeomeanPrice(address(usdt)));
        _easySwap(1e18);
        console2.log("Price (oracle) ::: %18e", hookOracleContract.getGeomeanPrice(address(usdt)));
    }
    /// -------- Helpers --------- ///

    function _easySwap(uint256 amount) public {
        skip(100);
        vm.roll(block.number + 1);
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
