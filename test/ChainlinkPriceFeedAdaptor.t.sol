// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import "forge-std/console2.sol";
import {Test} from "forge-std/Test.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

import {TestTwapBal} from "./helper/TestTwapBal.sol";
import {WeightedPool} from "lib/balancer-v3-monorepo/pkg/pool-weighted/contracts/WeightedPool.sol";
import {WeightedPoolGeomeanOracleHookContract} from
    "../contracts/WeightedPoolGeomeanOracleHookContract.sol";
import {ChainlinkPriceFeedAdaptor} from "../contracts/ChainlinkPriceFeedAdaptor.sol";
import {IChainlinkAggregatorV2V3} from "../contracts/interfaces/IChainlinkAggregatorV2V3.sol";
import {MockChainlinkAggregator} from "test/helper/MockChainlinkAggregator.sol";

contract ChainlinkPriceFeedAdaptorTest is TestTwapBal {
    WeightedPool public pool;
    IERC20[] public assets;
    WeightedPoolGeomeanOracleHookContract public hookOracleContract;
    ChainlinkPriceFeedAdaptor public adaptorUsdt;
    ChainlinkPriceFeedAdaptor public adaptorUsdtWithCL;
    MockChainlinkAggregator public mockChainlinkAggregatorUsdcUsd;

    // Constants for our tests
    uint256 constant OBSERVATION_PERIOD = 300; // 5 minutes

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
            address(vaultV3), address(weightedPoolFactory), address(referenceToken)
        );

        pool = WeightedPool(createWeightedPool(assets, address(hookOracleContract), address(this)));

        uint256[] memory amountsToAdd = new uint256[](assets.length);
        amountsToAdd[0] = 1_000_000e18;
        amountsToAdd[1] = 1_000_000e18;

        vm.prank(userA);
        router.initialize(address(pool), assets, amountsToAdd);
        vm.stopPrank();

        // Perform some swaps to populate the oracle with price data
        _performSwapsToGeneratePriceData(address(pool), hookOracleContract);

        // 1 USDC = 1 USD
        mockChainlinkAggregatorUsdcUsd = new MockChainlinkAggregator(8, "USDC / USD", 1e8);

        // Deploy the ChainlinkPriceFeedAdaptor for USDT
        adaptorUsdt = ChainlinkPriceFeedAdaptor(
            hookOracleContract.createChainlinkPriceFeedAdaptor(
                address(usdt), OBSERVATION_PERIOD, address(0)
            )
        );

        // USDT / USDC / USD
        adaptorUsdtWithCL = ChainlinkPriceFeedAdaptor(
            hookOracleContract.createChainlinkPriceFeedAdaptor(
                address(usdt), OBSERVATION_PERIOD, address(mockChainlinkAggregatorUsdcUsd)
            )
        );
    }

    function test_adaptorDeployment() public view {
        // Verify the adaptor was deployed correctly
        assertEq(
            address(adaptorUsdt.oracle()), address(hookOracleContract), "Oracle address mismatch"
        );
        assertEq(adaptorUsdt.token(), address(usdt), "Token address mismatch");
        assertEq(adaptorUsdt.observationPeriod(), OBSERVATION_PERIOD, "Observation period mismatch");
        assertEq(
            address(adaptorUsdt.chainlinkAggregator()), address(0), "Chainlink aggregator mismatch"
        );
    }

    function test_decimals() public view {
        // Reference token (USDC) decimals
        uint8 expectedDecimals = ERC20(address(usdc)).decimals();
        assertEq(adaptorUsdt.decimals(), expectedDecimals, "Decimals mismatch");
    }

    function test_description() public view {
        // Description should be "TOKEN/REFERENCE_TOKEN"
        string memory expectedDescription =
            string.concat(ERC20(address(usdt)).symbol(), " / ", ERC20(address(usdc)).symbol());
        assertEq(adaptorUsdt.description(), expectedDescription, "Description mismatch");
    }

    function test_latestAnswer() public view {
        // Should return the geomean price from the oracle
        int256 price = adaptorUsdt.latestAnswer();
        assertTrue(price > 0, "Price should be positive");

        // Compare with oracle's geomean price
        uint256 oraclePrice = hookOracleContract.getGeomeanPrice(address(usdt), OBSERVATION_PERIOD);
        assertEq(uint256(price), oraclePrice, "Price mismatch with oracle");
    }

    function test_latestTimestamp() public view {
        // Should return the current block timestamp
        assertEq(adaptorUsdt.latestTimestamp(), block.timestamp, "Timestamp mismatch");
    }

    function test_latestRound() public view {
        // Should return the current block timestamp as the round ID
        assertEq(adaptorUsdt.latestRound(), block.timestamp, "Round ID mismatch");
    }

    function test_latestRoundData() public view {
        // Get the latest round data
        (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = adaptorUsdt.latestRoundData();

        // Verify the values
        assertEq(roundId, uint80(block.timestamp), "Round ID mismatch");
        assertTrue(answer > 0, "Answer should be positive");
        assertEq(startedAt, 1, "Started at should be 1");
        assertEq(updatedAt, block.timestamp, "Updated at should be current timestamp");
        assertEq(answeredInRound, uint80(block.timestamp), "Answered in round mismatch");

        // Compare with oracle's geomean price
        uint256 oraclePrice = hookOracleContract.getGeomeanPrice(address(usdt), OBSERVATION_PERIOD);
        assertEq(uint256(answer), oraclePrice, "Price mismatch with oracle");
    }

    function test_unsupportedFunctions() public {
        // Test that unsupported functions revert
        vm.expectRevert(ChainlinkPriceFeedAdaptor.ChainlinkPriceFeedAdaptor__NOT_SUPPORTED.selector);
        adaptorUsdt.getAnswer(0);

        vm.expectRevert(ChainlinkPriceFeedAdaptor.ChainlinkPriceFeedAdaptor__NOT_SUPPORTED.selector);
        adaptorUsdt.getTimestamp(0);

        vm.expectRevert(ChainlinkPriceFeedAdaptor.ChainlinkPriceFeedAdaptor__NOT_SUPPORTED.selector);
        adaptorUsdt.getRoundData(0);
    }

    function test_createMultipleAdaptors() public {
        // Create another adaptor with different observation period
        uint256 newObservationPeriod = 600; // 10 minutes
        ChainlinkPriceFeedAdaptor adaptorUsdt2 = ChainlinkPriceFeedAdaptor(
            hookOracleContract.createChainlinkPriceFeedAdaptor(
                address(usdt), newObservationPeriod, address(0)
            )
        );

        // Verify the new adaptor has the correct observation period
        assertEq(
            adaptorUsdt2.observationPeriod(),
            newObservationPeriod,
            "New observation period mismatch"
        );

        // Prices should be different with different observation periods
        int256 price1 = adaptorUsdt.latestAnswer();
        int256 price2 = adaptorUsdt2.latestAnswer();

        // Log prices for debugging
        console2.log("Price with observation period %d: %d", OBSERVATION_PERIOD, uint256(price1));
        console2.log("Price with observation period %d: %d", newObservationPeriod, uint256(price2));

        assertApproxEqRel(price1, price2, 0.01e18, "Prices should be approximately equal");
    }

    // TODO test adaptorUsdtWithCL
}
