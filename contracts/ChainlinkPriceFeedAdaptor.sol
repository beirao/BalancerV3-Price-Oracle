// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {IChainlinkAggregatorV2V3} from "./interfaces/IChainlinkAggregatorV2V3.sol";
import {IGeomeanOracleHookContract} from "./interfaces/IGeomeanOracleHookContract.sol";

/**
 * @title ChainlinkPriceFeedAdaptor
 * @notice Adaptor contract that implements Chainlink's AggregatorV2V3 interface using geometric mean prices
 * @dev This contract replicates the behavior of Chainlink's AggregatorV2V3 interface.
 * Since the GeomeanOracleHookContract updates the price every second, we consider a round to be every second.
 * This means that a round ID is equivalent to the timestamp.
 * @dev Functions that ask for a specific round ID are not implemented. (`getAnswer()`, `getTimestamp()`, `getRoundData()`)
 */
contract ChainlinkPriceFeedAdaptor is IChainlinkAggregatorV2V3 {
    /// @notice Reference to the oracle hook contract that provides price data
    IGeomeanOracleHookContract public immutable oracle;

    /// @notice Address of the token for which this adaptor provides price data
    address public immutable token;

    /// @notice Time period over which the geometric mean price is calculated
    uint256 public immutable observationPeriod;

    /// @notice Optional reference to an actual Chainlink aggregator (for fallback or comparison)
    IChainlinkAggregatorV2V3 public immutable chainlinkAggregator;

    /// @notice Error thrown when an unsupported function is called
    error ChainlinkPriceFeedAdaptor__NOT_SUPPORTED();

    /**
     * @notice Constructs a new ChainlinkPriceFeedAdaptor
     * @param _token Address of the token for which to provide price data
     * @param _observationPeriod Time period (in seconds) over which to calculate the geometric mean price
     * @param _chainlinkAggregator Address of an optional Chainlink aggregator for reference
     */
    constructor(address _token, uint256 _observationPeriod, address _chainlinkAggregator) {
        oracle = IGeomeanOracleHookContract(msg.sender);
        token = _token;
        observationPeriod = _observationPeriod;
        chainlinkAggregator = IChainlinkAggregatorV2V3(_chainlinkAggregator);
    }

    /// -------- V2 -------- ///

    /**
     * @notice Returns the latest price as a signed integer
     * @return The geometric mean price of the token over the observation period
     */
    function latestAnswer() external view returns (int256) {
        return int256(oracle.getGeomeanPrice(token, observationPeriod));
    }

    /**
     * @notice Returns the timestamp of the latest price update
     * @return The current block timestamp
     */
    function latestTimestamp() external view returns (uint256) {
        return block.timestamp;
    }

    /**
     * @notice Returns the round ID of the latest price update
     * @return The current block timestamp (used as the round ID)
     */
    function latestRound() external view returns (uint256) {
        return block.timestamp;
    }

    /// @notice Not supported.
    function getAnswer(uint256) external pure returns (int256) {
        revert ChainlinkPriceFeedAdaptor__NOT_SUPPORTED();
    }

    /// @notice Not supported.
    function getTimestamp(uint256) external pure returns (uint256) {
        revert ChainlinkPriceFeedAdaptor__NOT_SUPPORTED();
    }

    /// -------- V3 -------- ///

    /**
     * @notice Returns the number of decimals in the price data
     * @return The number of decimals used by the reference token
     */
    function decimals() external view override returns (uint8) {
        return oracle.getReferenceTokenDecimals();
    }

    /**
     * @notice Returns a description of the price feed
     * @return A string in the format "TOKEN/REFERENCE_TOKEN"
     */
    function description() external view override returns (string memory) {
        return string.concat(ERC20(token).symbol(), "/", ERC20(oracle.getReferenceToken()).symbol());
    }

    /**
     * @notice Returns the version of the price feed
     * @return The version number (1)
     */
    function version() external pure override returns (uint256) {
        return 1;
    }

    /// @notice Not supported.
    function getRoundData(uint80)
        external
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        revert ChainlinkPriceFeedAdaptor__NOT_SUPPORTED();
    }

    /**
     * @notice Returns data about the latest round
     * @return roundId
     * @return answer The geomean price of the token over the observation period.
     * @return startedAt Theorically the pool creation timestamp but we just return 1 since
     * we don't have this information.
     * @return updatedAt Returns the current timestamp since we update the price every swap.
     * @return answeredInRound Returns the current timestamp. A second can be seen as a round
     * since the price is continuously updated.
     */
    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        return (
            uint80(block.timestamp),
            int256(oracle.getGeomeanPrice(token, observationPeriod)),
            1,
            block.timestamp,
            uint80(block.timestamp)
        );
    }
}
