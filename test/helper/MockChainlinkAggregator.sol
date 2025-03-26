// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

/**
 * @title MockChainlinkAggregator
 * @notice Mock implementation of Chainlink's Aggregator interface for testing
 */
contract MockChainlinkAggregator {
    // Configuration
    uint8 private _decimals;
    string private _description;
    uint256 private _version;

    // Current price data
    int256 private _answer;
    uint256 private _timestamp;
    uint256 private _roundId;

    // Historical data mapping
    mapping(uint256 => RoundData) private _roundData;

    struct RoundData {
        int256 answer;
        uint256 startedAt;
        uint256 updatedAt;
        uint80 answeredInRound;
        bool exists;
    }

    /**
     * @notice Constructor for the mock
     * @param decimals_ Number of decimals for the price data
     * @param description_ Description of the price feed
     * @param initialAnswer_ Initial price answer
     */
    constructor(uint8 decimals_, string memory description_, int256 initialAnswer_) {
        _decimals = decimals_;
        _description = description_;
        _version = 1;
        _answer = initialAnswer_;
        _timestamp = block.timestamp;
        _roundId = 1;

        // Set initial round data
        _roundData[_roundId] = RoundData({
            answer: initialAnswer_,
            startedAt: block.timestamp - 60, // 1 minute ago
            updatedAt: block.timestamp,
            answeredInRound: uint80(_roundId),
            exists: true
        });
    }

    /**
     * @notice Updates the current price
     * @param answer New price answer
     */
    function updateAnswer(int256 answer) external {
        _answer = answer;
        _timestamp = block.timestamp;
        _roundId++;

        // Update round data
        _roundData[_roundId] = RoundData({
            answer: answer,
            startedAt: block.timestamp - 10, // 10 seconds ago
            updatedAt: block.timestamp,
            answeredInRound: uint80(_roundId),
            exists: true
        });
    }

    function latestAnswer() external view returns (int256) {
        return _answer;
    }

    function decimals() external view returns (uint8) {
        return _decimals;
    }

    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        RoundData memory data = _roundData[_roundId];
        return (uint80(_roundId), data.answer, data.startedAt, data.updatedAt, data.answeredInRound);
    }
}
