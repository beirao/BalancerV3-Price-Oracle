// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/**
 * @title IGeomeanOracleHookContract
 * @notice Interface for all GeomeanOracleHookContract which provides geometric
 * mean pricing functionality for Balancer V3.
 */
interface IGeomeanOracleHookContract {
    // ============= STRUCTS =============

    /**
     * @notice Observation structure to store price data points
     * @param timestamp The timestamp when the observation was recorded
     * @param price The price at the time of the observation
     * @param accumulatedPrice The accumulated price for TWAP calculations
     */
    struct Observation {
        uint40 timestamp;
        uint216 price;
        int256 accumulatedPrice;
    }

    /**
     * @notice TokenData structure to store token-specific metadata
     * @param index The index of the token in the pool
     * @param lastBlockNumber The last block number when the price was updated
     */
    struct TokenData {
        uint8 index;
        uint248 lastBlockNumber;
    }

    // ============= EVENTS =============

    /**
     * @notice Emitted when the hook contract is registered with a pool
     * @param hook The address of the hook contract
     * @param pool The address of the pool
     */
    event GeomeanOracleHookContractRegistered(address indexed hook, address indexed pool);

    /**
     * @notice Emitted when a token price is updated
     * @param token The address of the token
     * @param price The updated price
     */
    event GeomeanOracleHookContractPriceUpdated(address indexed token, uint256 price);

    // ============= ERRORS =============

    /**
     * @notice Error thrown when trying to register a hook that is already registered
     */
    error GeomeanOracleHookContract__ALREADY_REGISTERED();

    /**
     * @notice Error thrown when the factory is not allowed to create pools with this hook
     * @param factory The address of the factory
     */
    error GeomeanOracleHookContract__FACTORY_NOT_ALLOWED(address factory);

    /**
     * @notice Error thrown when the pool was not created by the allowed factory
     * @param pool The address of the pool
     */
    error GeomeanOracleHookContract__POOL_NOT_FROM_FACTORY(address pool);

    /**
     * @notice Error thrown when the reference token is not supported
     */
    error GeomeanOracleHookContract__REFERENCE_TOKEN_NOT_SUPPORTED();

    /**
     * @notice Error thrown when there are not enough observations for a calculation
     * @param numberOfObservations The number of observations available
     */
    error GeomeanOracleHookContract__NOT_ENOUGH_OBSERVATIONS(uint256 numberOfObservations);

    // ============= VIEW FUNCTIONS =============

    function getReferenceToken() external view returns (address);

    function getObservation(address token, uint256 index)
        external
        view
        returns (uint40 timestamp, uint216 price, int256 accumulatedPrice);

    function getGeomeanPrice(address token, uint256 observationPeriod)
        external
        view
        returns (uint256);

    function getGeomeanPrice(address token, uint256 observationPeriod, uint256 hintLow)
        external
        view
        returns (uint256);

    function getLastPrice(address token) external view returns (uint256);
}
