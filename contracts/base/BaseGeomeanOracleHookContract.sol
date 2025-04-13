// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// OpenZeppelin imports.
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

/// Solmate imports.
import {FixedPointMathLib} from "lib/solmate/src/utils/FixedPointMathLib.sol";
import {wadExp, wadLn} from "lib/solmate/src/utils/SignedWadMath.sol";
import {SafeCastLib} from "lib/solmate/src/utils/SafeCastLib.sol";

/// Balancer V3 imports.
import {IVault} from "lib/balancer-v3-monorepo/pkg/interfaces/contracts/vault/IVault.sol";
import {VaultGuard} from "lib/balancer-v3-monorepo/pkg/vault/contracts/VaultGuard.sol";
import {BaseHooks} from "lib/balancer-v3-monorepo/pkg/vault/contracts/BaseHooks.sol";
import {
    TokenConfig,
    LiquidityManagement,
    HookFlags,
    AfterSwapParams
} from "lib/balancer-v3-monorepo/pkg/interfaces/contracts/vault/VaultTypes.sol";
import {BasePoolFactory} from
    "lib/balancer-v3-monorepo/pkg/pool-utils/contracts/BasePoolFactory.sol";

/// Project imports.
import {IGeomeanOracleHookContract} from "../interfaces/IGeomeanOracleHookContract.sol";
import {ChainlinkPriceFeedAdaptor} from "./ChainlinkPriceFeedAdaptor.sol";

abstract contract BaseGeomeanOracleHookContract is
    IGeomeanOracleHookContract,
    BaseHooks,
    VaultGuard
{
    using FixedPointMathLib for uint256;
    using SafeCastLib for uint256;

    /// @notice The number of decimals in the WAD (18).
    uint256 internal constant WAD_DECIMALS = 18;

    /// @notice The number of decimals in the WAD (18).
    uint256 internal constant WAD = 1e18;

    /// @notice The maximum observation period.
    uint256 public constant MAX_OBSERVATION_PERIOD = 30 days;

    /// @notice The maximum price change between two observations (WAD = 100%).
    uint256 public constant MAX_INTER_OBSERVATION_PRICE_CHANGE = 1e17; // 10%

    /// @notice Mapping from token address to its metadata.
    mapping(address => TokenData) internal tokenToData;

    /// @notice Mapping from token address to its price observations history.
    mapping(address => Observation[]) internal tokenToObservations;

    /// @notice Address of the token used as reference for price calculations.
    address internal immutable referenceToken;

    /// @notice Address of the Balancer V3 Vault.
    address internal immutable vault;

    /// @notice Address of the pool using this hook.
    address internal pool;

    /**
     * @notice Initializes the oracle hook contract.
     * @param _vault The address of the Balancer V3 Vault.
     * @param _referenceToken The address of the token to use as reference for price calculations.
     */
    constructor(address _vault, address _referenceToken) VaultGuard(IVault(_vault)) {
        vault = _vault;
        referenceToken = _referenceToken;
    }

    /// @inheritdoc BaseHooks
    function onRegister(
        address _factory,
        address _pool,
        TokenConfig[] memory _tokenConfigs,
        LiquidityManagement calldata
    ) public override onlyVault returns (bool) {
        if (pool != address(0)) {
            revert GeomeanOracleHookContract__ALREADY_REGISTERED();
        }
        pool = _pool;

        // Check if pool was created by the allowed factory.
        if (!BasePoolFactory(_factory).isPoolFromFactory(_pool)) {
            revert GeomeanOracleHookContract__POOL_NOT_FROM_FACTORY(_pool);
        }

        bool isReferenceTokenIncluded_;
        // Check if all tokens are included in the pool and in the correct order.
        for (uint256 i; i < _tokenConfigs.length; i++) {
            address token_ = address(_tokenConfigs[i].token);

            // Initialize tokenToIndex.
            tokenToData[token_] =
                TokenData({index: uint8(i), lastBlockNumber: uint248(block.number)});

            // Check if reference token is included in the pool.
            if (token_ == referenceToken) {
                isReferenceTokenIncluded_ = true;
            }

            // Initialize observations.
            // AccumulatedPrice is 0 because we don't have any price data yet.
            // The oracle will be safe once the observation period has passed.
            if (token_ != referenceToken) {
                tokenToObservations[token_].push(
                    Observation({
                        timestamp: uint40(block.timestamp),
                        scaled18Price: uint216(WAD),
                        accumulatedPrice: 0
                    })
                );
            }
        }

        if (!isReferenceTokenIncluded_) {
            revert GeomeanOracleHookContract__REFERENCE_TOKEN_NOT_SUPPORTED();
        }

        emit GeomeanOracleHookContractRegistered(address(this), _pool);

        return true;
    }

    /// @inheritdoc BaseHooks
    function getHookFlags() public pure override returns (HookFlags memory hookFlags_) {
        hookFlags_.shouldCallAfterSwap = true;
        return hookFlags_;
    }

    /// @inheritdoc BaseHooks
    function onAfterSwap(AfterSwapParams calldata params_)
        public
        override
        onlyVault
        returns (bool, uint256)
    {
        // Update prices of the tokens swapped.
        if (address(params_.tokenIn) != referenceToken) {
            _updatePrice(address(params_.tokenIn));
        }

        if (address(params_.tokenOut) != referenceToken) {
            _updatePrice(address(params_.tokenOut));
        }

        return (true, 0);
    }
    /**
     * @notice Creates a new Chainlink price feed adaptor for a specific token
     * @dev The Chainlink price feed base tokens needs to be the same as the reference token.
     * @param _token The address of the token for which to create the adaptor
     * @param _observationPeriod The period over which observations will be made, must be <= MAX_OBSERVATION_PERIOD
     * @param _chainlinkAggregator The address of the Chainlink price feed aggregator to convert the price from the
     *        reference token to the chainlink price feed quote token.
     * @return The address of the newly created ChainlinkPriceFeedAdaptor
     */

    function createChainlinkPriceFeedAdaptor(
        address _token,
        uint256 _observationPeriod,
        address _chainlinkAggregator
    ) external returns (address) {
        // Check `_token` is different from `referenceToken`.
        if (_token == referenceToken) {
            revert GeomeanOracleHookContract__TOKEN_IS_REFERENCE_TOKEN();
        }

        // Check if `_token` is included in the pool.
        if (tokenToData[_token].lastBlockNumber == 0) {
            revert GeomeanOracleHookContract__TOKEN_NOT_INCLUDED_IN_THE_POOL();
        }

        // Check the observation period is between the minimum and maximum allowed.
        if (_observationPeriod > MAX_OBSERVATION_PERIOD) {
            revert GeomeanOracleHookContract__WRONG_OBSERVATION_PERIOD();
        }

        emit GeomeanOracleHookContractChainlinkPriceFeedAdaptorCreated(
            _token, _observationPeriod, _chainlinkAggregator
        );

        return address(
            new ChainlinkPriceFeedAdaptor(
                _token, address(this), _observationPeriod, _chainlinkAggregator
            )
        );
    }

    // ============= VIEW FUNCTIONS =============

    /**
     * @notice Get the address of the reference token.
     * @return The address of the reference token.
     */
    function getReferenceToken() external view returns (address) {
        return referenceToken;
    }

    /**
     * @notice Get the decimals of the reference token.
     * @dev This represents the number of decimals in returned prices.
     * @return The decimals of the reference token.
     */
    function getReferenceTokenDecimals() external view returns (uint8) {
        return ERC20(referenceToken).decimals();
    }

    /**
     * @notice Get a specific observation for a token.
     * @param _token The address of the token.
     * @param _index The index of the observation to retrieve.
     * @return timestamp_ The timestamp of the observation.
     * @return scaled18Price_ The scaled to 18 decimals price at the time of the observation.
     * @return accumulatedPrice_ The accumulated price for TWAP calculations.
     */
    function getObservation(address _token, uint256 _index)
        external
        view
        returns (uint40, uint216, int256)
    {
        Observation memory observation_ = tokenToObservations[_token][_index];
        return (observation_.timestamp, observation_.scaled18Price, observation_.accumulatedPrice);
    }

    /**
     * @notice Get the latest observation for a token.
     * @param _token The address of the token.
     * @return timestamp_ The timestamp of the observation.
     * @return scaled18Price_ The scaled to 18 decimals price at the time of the observation.
     * @return accumulatedPrice_ The accumulated price for TWAP calculations.
     * @return numberOfObservations_ The number of observations.
     */
    function getLatestObservation(address _token)
        external
        view
        returns (uint40, uint216, int256, uint256)
    {
        uint256 numberOfObservations_ = tokenToObservations[_token].length - 1;
        Observation[] storage observations = tokenToObservations[_token];
        Observation memory observation_ = observations[numberOfObservations_];
        return (
            observation_.timestamp,
            observation_.scaled18Price,
            observation_.accumulatedPrice,
            numberOfObservations_
        );
    }

    /**
     * @notice Get the geometric mean price of a token over a specified period.
     * @dev Geomean price = ∏(x_i^ΔT_i)^(1/n)
     *                    = exp(Σ(ΔT_i * ln(price_i)) / n)
     * @dev Geomean price over a period = exp(accumulatedPrice(timestamp - period) - accumulatedPrice(timestamp)) / observationPeriod_)
     * @param _token The address of the token.
     * @param observationPeriod_ The period in seconds over which to calculate the geometric mean.
     * @return geomeanPrice_ The geometric mean price of the token over the specified period.
     */
    function getGeomeanPrice(address _token, uint256 observationPeriod_)
        external
        view
        returns (uint256)
    {
        return getGeomeanPrice(_token, observationPeriod_, 0);
    }

    /**
     * @notice Get the geometric mean price of a token over a specified period with a hint.
     * @param _token The address of the token.
     * @param _observationPeriod The period in seconds over which to calculate the geometric mean.
     * @param _hintLow A hint for the binary search to optimize performance.
     * @return geomeanPrice_ The geometric mean price of the token over the specified period.
     */
    function getGeomeanPrice(address _token, uint256 _observationPeriod, uint256 _hintLow)
        public
        view
        returns (uint256)
    {
        // Check the observation period is between the minimum and maximum allowed.
        if (_observationPeriod > MAX_OBSERVATION_PERIOD) {
            revert GeomeanOracleHookContract__WRONG_OBSERVATION_PERIOD();
        }

        Observation[] storage observations = tokenToObservations[_token];
        Observation storage observationsNow = observations[observations.length - 1];
        uint256 startPeriodTimestamp_ = block.timestamp - _observationPeriod;
        Observation storage observationsPeriodStart =
            observations[_binarySearch(observations, startPeriodTimestamp_, _hintLow)];

        int256 averageLogPrice_ = _calculateAccumulatedPrice(observationsNow, block.timestamp)
            - _calculateAccumulatedPrice(observationsPeriodStart, startPeriodTimestamp_);

        return _unscalePrice(uint256(wadExp(averageLogPrice_ / int256(_observationPeriod))));
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                                        ∂f                                 //
    //                                                      -------                              //
    // f = Invariant function                                 ∂x                                 //
    // x = Base reserve                Spot Price = df =  -----------                            //
    // y = Quote reserve                                      ∂f                                 //
    //                                                      -------                              //
    //                                                        ∂y                                 //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    /**
     * @notice Get the latest price of a token using reserve balances.
     * @dev THE RETURNED PRICE IS EASY TO MANIPULATE. USE `getGeomeanPrice()` INSTEAD.
     * @param _token The address of the token.
     * @return latestPrice_ The latest price of the token in units of the reference token.
     */
    function getLastPrice(address _token) public view virtual returns (uint256);

    // ============= INTERNAL FUNCTIONS =============

    /**
     * @notice Converts a price from 18 decimals to the reference token's decimal precision.
     * @param _scaled18Price The price in 18 decimal (WAD) format.
     * @return The price adjusted to the reference token's decimal precision.
     */
    function _unscalePrice(uint256 _scaled18Price) internal view returns (uint256) {
        uint8 referenceTokenDecimals_ = ERC20(referenceToken).decimals();
        if (referenceTokenDecimals_ >= WAD_DECIMALS) {
            return _scaled18Price * 10 ** (referenceTokenDecimals_ - WAD_DECIMALS);
        } else {
            return _scaled18Price / 10 ** (WAD_DECIMALS - referenceTokenDecimals_);
        }
    }

    /**
     * @notice Calculate the accumulated price based on the previous observation, timestamp and price.
     * @param observation The observation containing timestamp and accumulatedPrice.
     * @param _timestamp The timestamp for which to calculate the accumulatedPrice.
     * @return accumulatedPrice_ The calculated accumulated price.
     */
    function _calculateAccumulatedPrice(Observation storage observation, uint256 _timestamp)
        internal
        view
        returns (int256)
    {
        return observation.accumulatedPrice
            + (int256(_timestamp - observation.timestamp)) * wadLn(int216(observation.scaled18Price)); // Safe cast.
    }

    /**
     * @notice Updates the price of a token based on the current pool state.
     * @param _tokenAddress The address of the token to update.
     */
    function _updatePrice(address _tokenAddress) internal {
        Observation[] storage tokenToObservation = tokenToObservations[_tokenAddress];
        Observation storage lastObservation = tokenToObservation[tokenToObservation.length - 1];

        uint256 lastPrice_ = getLastPrice(_tokenAddress);

        // Update observations with the last accumulatedPrice of a new block.
        // So we have maximum 1 observation per block.
        if (tokenToData[_tokenAddress].lastBlockNumber != block.number) {
            lastPrice_ = _manipulationSafeGuard(lastPrice_, lastObservation.scaled18Price);

            tokenToObservation.push(
                Observation({
                    timestamp: uint40(block.timestamp),
                    scaled18Price: lastPrice_.safeCastTo216(),
                    accumulatedPrice: _calculateAccumulatedPrice(lastObservation, block.timestamp)
                })
            );

            tokenToData[_tokenAddress].lastBlockNumber = uint248(block.number);
        } else {
            Observation storage secondLastObservation =
                tokenToObservation[tokenToObservation.length - 2];
            lastPrice_ = _manipulationSafeGuard(lastPrice_, secondLastObservation.scaled18Price);

            lastObservation.accumulatedPrice =
                _calculateAccumulatedPrice(secondLastObservation, block.timestamp);
            lastObservation.scaled18Price = lastPrice_.safeCastTo216();
            // We don't need to update the timestamp because it stays the same within the same block.
        }

        emit GeomeanOracleHookContractPriceUpdated(_tokenAddress, lastPrice_);
    }

    /**
     * @notice Performs a manipulation safe guard check on the price.
     * @dev This relies on the simple assumption that if the price changes by more than MAX_INTER_OBSERVATION_PRICE_CHANGE
     *      in a single block, it is either market manipulation or an inefficient swap. In both cases, applying the
     *      `_manipulationSafeGuard()` filter is appropriate to protect the oracle from extreme price movements.
     * @param _currentPrice The current price.
     * @param _lastPrice The last price.
     * @return The price after the manipulation safe guard check.
     */
    function _manipulationSafeGuard(uint256 _currentPrice, uint256 _lastPrice)
        internal
        pure
        returns (uint256)
    {
        uint256 minPrice_ = _lastPrice.mulWadDown(WAD - MAX_INTER_OBSERVATION_PRICE_CHANGE);
        uint256 maxPrice_ = _lastPrice.mulWadDown(WAD + MAX_INTER_OBSERVATION_PRICE_CHANGE);

        // If manipulation is detected, return max/min allowed price.
        if (_currentPrice > maxPrice_) {
            return maxPrice_;
        } else if (_currentPrice < minPrice_) {
            return minPrice_;
        }
        return _currentPrice;
    }

    /**
     * @notice Performs a binary search to find the observation closest to the target timestamp.
     * @dev Uses a hint to optimize the search by starting from a specific index. If the hint is invalid,
     *      default to 0.
     * @param observations The array of observations to search through.
     * @param _targetTimestamp The timestamp to search for.
     * @param _hintLow A hint for where to start the search (optimization). 0 if you don't have a hint.
     * @return index_ The index of the observation closest to but not exceeding the target timestamp.
     */
    function _binarySearch(
        Observation[] storage observations,
        uint256 _targetTimestamp,
        uint256 _hintLow
    ) internal view returns (uint256) {
        uint256 lastIndex_ = observations.length - 1;

        if (observations.length == 0 || _targetTimestamp <= observations[0].timestamp) {
            revert GeomeanOracleHookContract__NOT_ENOUGH_OBSERVATIONS(lastIndex_ + 1);
        }

        // Check if _hintLow is valid. If not default to 0.
        if (_hintLow > lastIndex_ || observations[_hintLow].timestamp > _targetTimestamp) {
            _hintLow = 0;
        }

        // If target timestamp is after the latest observation, return the latest.
        if (_targetTimestamp >= observations[lastIndex_].timestamp) {
            return lastIndex_;
        }

        // Binary search to find the closest observation.
        uint256 low_ = _hintLow; // Hint low allows to skip the first part of the array. 0 if you don't have a hint.
        uint256 high_ = lastIndex_;

        while (low_ < high_) {
            uint256 mid_ = (low_ + high_) / 2;

            if (observations[mid_].timestamp == _targetTimestamp) {
                return mid_; // Exact match
            } else if (observations[mid_].timestamp < _targetTimestamp) {
                low_ = mid_ + 1;
            } else {
                high_ = mid_;
            }
        }

        // At this point, low == high_
        // If the timestamp at low is greater than target, we need the previous observation.
        if (observations[low_].timestamp > _targetTimestamp) {
            return low_ - 1;
        }

        return low_;
    }

    /**
     * @notice Calculates the partial derivative of the invariant function with respect to a token.
     * @dev This function is implemented by derived contracts based on their specific pool math.
     * @param lastBalancesWad_ The array of token balances in WAD format.
     * @param tokenIndex_ The index of the token in the pool.
     * @param tokenWeight_ The normalized weight of the token in the pool. (only for WeightedPool)
     * @return The partial derivative value used in price calculations.
     */
    function _calculatePartialDerivative(
        uint256[] memory lastBalancesWad_,
        uint256 tokenIndex_,
        uint256 tokenWeight_
    ) internal view virtual returns (uint256);
}
