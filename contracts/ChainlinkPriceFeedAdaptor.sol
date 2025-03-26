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
 * @dev If the chainlinkAggregator is not set, the adaptor will use the reference token from the oracle hook contract. If
 * the chainlinkAggregator is set, this contract will use it to convert the price to chainlink quote token.
 *
 * ATTENTION: The chainlinkAggregator must be a Chainlink aggregator must be compatible with the `referenceToken` of
 * the oracle hook contract. For example, if `referenceToken` is ETH, the chainlinkAggregator must be a Chainlink aggregator
 * that has ETH as the base token. (Ex: ETH/USD) So by providing a chainlinkAggregator, the adaptor will convert the price
 * to the chainlink quote token instead of the reference token. (Ex: twap(ETH/USDC) + chainlink(USDC/USD) => ETH/USD)
 */
contract ChainlinkPriceFeedAdaptor is IChainlinkAggregatorV2V3 {
    /// @notice Reference to the oracle hook contract that provides price data.
    IGeomeanOracleHookContract public immutable oracle;

    /// @notice Address of the token for which this adaptor provides price data.
    address public immutable token;

    /// @notice Time period over which the geometric mean price is calculated.
    uint256 public immutable observationPeriod;

    /// @notice Optional reference to an actual Chainlink aggregator (for fallback or comparison).
    IChainlinkAggregatorV2V3 public immutable chainlinkAggregator;

    /// @notice Error thrown when an unsupported function is called.
    error ChainlinkPriceFeedAdaptor__NOT_SUPPORTED();

    /// @notice Error thrown when the price feed is inconsistent.
    error ChainlinkPriceFeedAdaptor__INCONSISTENT_PRICE_FEED();

    /**
     * @notice Constructs a new ChainlinkPriceFeedAdaptor
     * @param _token Address of the token for which to provide price data.
     * @param _observationPeriod Time period (in seconds) over which to calculate the geometric mean price.
     * @param _chainlinkAggregator Address of an optional Chainlink aggregator for reference.
     */
    constructor(
        address _token,
        address _oracle,
        uint256 _observationPeriod,
        address _chainlinkAggregator
    ) {
        oracle = IGeomeanOracleHookContract(_oracle);
        token = _token;
        observationPeriod = _observationPeriod;
        chainlinkAggregator = IChainlinkAggregatorV2V3(_chainlinkAggregator);
    }

    /// -------- V2 -------- ///

    /**
     * @notice Returns the latest price as a signed integer.
     * @return The geometric mean price of the token over the observation period.
     */
    function latestAnswer() external view returns (int256) {
        int256 twapPrice_ = int256(oracle.getGeomeanPrice(token, observationPeriod));

        if (address(chainlinkAggregator) != address(0)) {
            return
                _convertPriceToChainlinkQuoteToken(twapPrice_, chainlinkAggregator.latestAnswer());
        }
        return twapPrice_;
    }

    /**
     * @notice Returns the timestamp of the latest price update.
     * @dev If a Chainlink aggregator is configured, delegates to its latestTimestamp function.
     * @return The current block timestamp.
     */
    function latestTimestamp() external view returns (uint256) {
        if (address(chainlinkAggregator) != address(0)) {
            return chainlinkAggregator.latestTimestamp();
        }
        return block.timestamp;
    }

    /**
     * @notice Returns the round ID of the latest price update.
     * @dev If a Chainlink aggregator is configured, delegates to its latestRound function.
     * @return The current block timestamp (used as the round ID).
     */
    function latestRound() external view returns (uint256) {
        if (address(chainlinkAggregator) != address(0)) {
            return chainlinkAggregator.latestRound();
        }
        return block.timestamp;
    }

    /// @notice Not supported.
    function getAnswer(uint256) external pure returns (int256) {
        revert ChainlinkPriceFeedAdaptor__NOT_SUPPORTED();
    }

    /**
     * @notice Returns the timestamp for a given round ID.
     * @dev If a Chainlink aggregator is configured, delegates to its getTimestamp function.
     * @param _roundId The round ID to get the timestamp for.
     * @return The timestamp for the specified round.
     * @dev Reverts with ChainlinkPriceFeedAdaptor__NOT_SUPPORTED if no Chainlink aggregator is set.
     */
    function getTimestamp(uint256 _roundId) external view returns (uint256) {
        if (address(chainlinkAggregator) != address(0)) {
            return chainlinkAggregator.getTimestamp(_roundId);
        }
        revert ChainlinkPriceFeedAdaptor__NOT_SUPPORTED();
    }

    /// -------- V3 -------- ///

    /**
     * @notice Returns the number of decimals in the price data.
     * @dev If a Chainlink aggregator is configured, delegates to its decimals function.
     * @return The number of decimals used by the reference token.
     */
    function decimals() external view override returns (uint8) {
        if (address(chainlinkAggregator) != address(0)) {
            return chainlinkAggregator.decimals();
        }
        return oracle.getReferenceTokenDecimals();
    }

    /**
     * @notice Returns a description of the price feed.
     * @dev If a Chainlink aggregator is configured, we use it to get the description.
     * @return A string in the format "TOKEN/REFERENCE_TOKEN".
     */
    function description() external view override returns (string memory) {
        if (address(chainlinkAggregator) != address(0)) {
            return string.concat(ERC20(token).symbol(), " / ", chainlinkAggregator.description()); // Ex: "ETH / USDC / USD" <=> "ETH / USD"
        }
        return
            string.concat(ERC20(token).symbol(), " / ", ERC20(oracle.getReferenceToken()).symbol()); // Ex: "ETH / USDC"
    }

    /**
     * @notice Returns the version of the price feed.
     * @return The version number (1).
     */
    function version() external pure override returns (uint256) {
        return 1;
    }

    /// @notice Not supported.
    function getRoundData(uint80)
        external
        pure
        returns (uint80, int256, uint256, uint256, uint80)
    {
        revert ChainlinkPriceFeedAdaptor__NOT_SUPPORTED();
    }

    /**
     * @notice Returns data about the latest round.
     * @return roundId_ The current timestamp. A second can be seen as a round since the price is continuously updated.
     * @return answer_ The geomean price of the token over the observation period.
     * @return startedAt_ Theorically the pool creation timestamp but we just return 1 since
     * we don't have this information.
     * @return updatedAt_ Returns the current timestamp since we update the price every swap.
     * @return answeredInRound_ Returns the current timestamp. A second can be seen as a round
     * since the price is continuously updated.
     */
    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        int256 twapPrice_ = int256(oracle.getGeomeanPrice(token, observationPeriod));

        if (address(chainlinkAggregator) != address(0)) {
            (
                uint80 roundId_,
                int256 clPrice_,
                uint256 startedAt_,
                uint256 updatedAt_,
                uint80 answeredInRound_
            ) = chainlinkAggregator.latestRoundData();

            return (
                roundId_,
                _convertPriceToChainlinkQuoteToken(twapPrice_, clPrice_),
                startedAt_,
                updatedAt_,
                answeredInRound_
            );
        }

        return (uint80(block.timestamp), twapPrice_, 1, block.timestamp, uint80(block.timestamp));
    }

    /**
     * @notice Convert a price from reference token to Chainlink quote token.
     * @dev Uses a Chainlink price feed to convert the price from the reference token to the quote token.
     * Example: If the price is in USDC and Chainlink feed gives USDC/USD, we convert to USD.
     * @dev We just check that _chainlinkPrice is positive to avoid division by zero or negative numbers.
     * @dev We ignore the Chainlink round parameters, but they could be used for validation.
     * (Ex: roundId == 0 || timestamp == 0 || timestamp > block.timestamp || price <= 0 ||
     *  startedAt == 0 || block.timestamp - timestamp > timeout => revert())
     * @param _twapPrice The price to convert, denominated in the reference token.
     * @param _chainlinkPrice The price from Chainlink latestRoundData.
     */
    function _convertPriceToChainlinkQuoteToken(int256 _twapPrice, int256 _chainlinkPrice)
        internal
        view
        returns (int256)
    {
        // Make sure the Chainlink price is positive to avoid division by zero or negative numbers.
        if (_chainlinkPrice <= 0) {
            revert ChainlinkPriceFeedAdaptor__INCONSISTENT_PRICE_FEED();
        }

        return int256(
            (_twapPrice * _chainlinkPrice) / int256(10 ** oracle.getReferenceTokenDecimals())
        );
    }
}
