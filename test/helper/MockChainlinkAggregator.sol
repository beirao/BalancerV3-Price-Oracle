// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

/**
 * @title MockChainlinkAggregator
 * @notice Mock implementation of Chainlink's Aggregator interface for testing
 */
contract MockChainlinkAggregator {
    // Configuration
    uint8 private dec;
    string private des;
    uint256 private ver;

    // Current price data
    int256 private answer;
    uint256 private timestamp;
    uint256 private roundId;

    // Historical data mapping
    mapping(uint256 => RoundData) private roundData;

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
        dec = decimals_;
        des = description_;
        ver = 1;
        answer = initialAnswer_;
        timestamp = block.timestamp;
        roundId = 1;

        // Set initial round data
        roundData[roundId] = RoundData({
            answer: initialAnswer_,
            startedAt: block.timestamp - 60, // 1 minute ago
            updatedAt: block.timestamp,
            answeredInRound: uint80(roundId),
            exists: true
        });
    }

    function description() external view returns (string memory) {
        return des;
    }

    function version() external view returns (uint256) {
        return ver;
    }

    /**
     * @notice Updates the current price
     * @param answer New price answer
     */
    function updateAnswer(int256 answer) external {
        answer = answer;
        timestamp = block.timestamp;
        roundId++;

        // Update round data
        roundData[roundId] = RoundData({
            answer: answer,
            startedAt: block.timestamp - 10, // 10 seconds ago
            updatedAt: block.timestamp,
            answeredInRound: uint80(roundId),
            exists: true
        });
    }

    function latestAnswer() external view returns (int256) {
        return answer;
    }

    function decimals() external view returns (uint8) {
        return dec;
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
        RoundData memory data = roundData[roundId];
        return (uint80(roundId), data.answer, data.startedAt, data.updatedAt, data.answeredInRound);
    }
}
