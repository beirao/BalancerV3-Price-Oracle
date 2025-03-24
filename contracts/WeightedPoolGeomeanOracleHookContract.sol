// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

// TODO: Remove this
import "forge-std/console2.sol";

import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
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
import {WeightedPoolImmutableData} from
    "lib/balancer-v3-monorepo/pkg/interfaces/contracts/pool-weighted/IWeightedPool.sol";
import {WeightedPool} from "lib/balancer-v3-monorepo/pkg/pool-weighted/contracts/WeightedPool.sol";
import "lib/solmate/src/utils/FixedPointMathLib.sol";
import "lib/solmate/src/utils/SignedWadMath.sol";
import "lib/solmate/src/utils/SafeCastLib.sol";
import {IGeomeanOracleHookContract} from "./interfaces/IWeightedPoolGeomeanOracleHookContract.sol";

contract WeightedPoolGeomeanOracleHookContract is
    IGeomeanOracleHookContract,
    BaseHooks,
    VaultGuard
{
    using FixedPointMathLib for uint256;
    using SafeCastLib for uint256;

    /// @notice Mapping from token address to its metadata
    mapping(address => TokenData) internal tokenToData;

    /// @notice Mapping from token address to its price observations history.
    mapping(address => Observation[]) internal tokenToObservations;

    /// @notice Address of the factory allowed to create pools with this hook.
    address internal immutable allowedFactory; //? useless since we can only register once?

    /// @notice Address of the token used as reference for price calculations.
    address internal immutable referenceToken;

    /// @notice Address of the Balancer V3 Vault.
    address internal immutable vault;

    /// @notice Address of the pool using this hook.
    address internal pool;

    /**
     * @notice Initializes the oracle hook contract.
     * @param _vault The address of the Balancer V3 Vault.
     * @param _allowedFactory The address of the WeightedPool factory that is allowed to create pools with this hook.
     * @param _referenceToken The address of the token to use as reference for price calculations.
     */
    constructor(address _vault, address _allowedFactory, address _referenceToken)
        VaultGuard(IVault(_vault))
    {
        vault = _vault;
        allowedFactory = _allowedFactory;
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

        // Check if factory is allowed.
        if (_factory != allowedFactory) {
            revert GeomeanOracleHookContract__FACTORY_NOT_ALLOWED(_factory);
        }

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
                        price: 1e18,
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
    function getHookFlags() public pure override returns (HookFlags memory hookFlags) {
        hookFlags.shouldCallAfterSwap = true;
        return hookFlags;
    }

    /// @inheritdoc BaseHooks
    function onAfterSwap(AfterSwapParams calldata params)
        public
        override
        onlyVault
        returns (bool, uint256)
    {
        uint256[] memory indexToWeight_ = WeightedPool(params.pool).getNormalizedWeights();
        uint256 referenceTokenIndex_ = tokenToData[referenceToken].index;
        (,,, uint256[] memory lastBalancesWad_) = IVault(vault).getPoolTokenInfo(params.pool);
        uint256 denominator_ =
            lastBalancesWad_[referenceTokenIndex_].divWadDown(indexToWeight_[referenceTokenIndex_]);

        // Update prices of the tokens swapped.
        if (address(params.tokenIn) != referenceToken) {
            uint256 tokenInIndex_ = tokenToData[address(params.tokenIn)].index;
            _updatePrice(
                address(params.tokenIn),
                tokenInIndex_,
                indexToWeight_[tokenInIndex_],
                lastBalancesWad_,
                denominator_
            );
        }

        if (address(params.tokenOut) != referenceToken) {
            uint256 tokenOutIndex_ = tokenToData[address(params.tokenOut)].index;
            _updatePrice(
                address(params.tokenOut),
                tokenOutIndex_,
                indexToWeight_[tokenOutIndex_],
                lastBalancesWad_,
                denominator_
            );
        }

        return (true, 0);
    }

    // ============= VIEW FUNCTIONS =============

    /**
     * @notice Get the address of the reference token
     * @return The address of the reference token
     */
    function getReferenceToken() public view returns (address) {
        return referenceToken;
    }

    /**
     * @notice Get a specific observation for a token
     * @param token_ The address of the token
     * @param index_ The index of the observation to retrieve
     * @return timestamp The timestamp of the observation
     * @return price The price at the time of the observation
     * @return accumulatedPrice The accumulated price for TWAP calculations
     */
    function getObservation(address token_, uint256 index_)
        public
        view
        returns (uint40 timestamp, uint216 price, int256 accumulatedPrice)
    {
        Observation memory observation = tokenToObservations[token_][index_];
        return (observation.timestamp, observation.price, observation.accumulatedPrice);
    }

    /**
     * @notice Get the geometric mean price of a token over a specified period
     * @dev Geomean price = ∏(x_i^ΔT_i)^(1/n)
     *                    = exp(Σ(ΔT_i * ln(price_i)) / n)
     * @dev Geomean price over a period = exp(accumulatedPrice(timestamp - period) - accumulatedPrice(timestamp)) / observationPeriod_)
     * @param token_ The address of the token
     * @param observationPeriod_ The period in seconds over which to calculate the geometric mean
     * @return The geometric mean price of the token over the specified period
     */
    function getGeomeanPrice(address token_, uint256 observationPeriod_)
        external
        view
        returns (uint256)
    {
        return getGeomeanPrice(token_, observationPeriod_, 0);
    }

    /**
     * @notice Get the geometric mean price of a token over a specified period with a hint
     * @param token_ The address of the token
     * @param observationPeriod_ The period in seconds over which to calculate the geometric mean
     * @param hintLow_ A hint for the binary search to optimize performance
     * @return The geometric mean price of the token over the specified period
     */
    function getGeomeanPrice(address token_, uint256 observationPeriod_, uint256 hintLow_)
        public
        view
        returns (uint256)
    {
        Observation[] storage observations = tokenToObservations[token_];
        Observation storage observationsNow = observations[observations.length - 1];
        uint256 startPeriodTimestamp_ = block.timestamp - observationPeriod_;
        Observation storage observationsPeriodStart =
            observations[_binarySearch(observations, startPeriodTimestamp_, hintLow_)];

        int256 numerator_ = _calculateAccumulatedPrice(observationsNow, block.timestamp)
            - _calculateAccumulatedPrice(observationsPeriodStart, startPeriodTimestamp_);

        return uint256(wadExp(numerator_ / int256(observationPeriod_)));
    }

    /**
     * @notice Get the latest price of a token
     * @dev THE RETURNED PRICE IS EASY TO MANIPULATE. USE `getGeomeanPrice()` INSTEAD.
     * @param token_ The address of the token
     * @return The latest price of the token in units of the reference token
     */
    function getLastPrice(address token_) public view returns (uint256) {
        Observation[] storage observations = tokenToObservations[token_];
        return observations[observations.length - 1].price; // TODO: scale to reference token decimals
    }

    // ============= INTERNAL FUNCTIONS =============

    /**
     * @notice Calculate the accumulated price based on the previous observation, timestamp and price.
     * @param observation The observation containing timestamp and accumulatedPrice.
     * @param timestamp_ The timestamp for which to calculate the accumulatedPrice.
     * @return The calculated accumulated price.
     */
    function _calculateAccumulatedPrice(Observation storage observation, uint256 timestamp_)
        internal
        view
        returns (int256)
    {
        return observation.accumulatedPrice
            + (int256(timestamp_ - observation.timestamp)) * wadLn(int216(observation.price)); // Safe cast.
    }

    /**
     * @notice Updates the price of a token based on the current pool state
     * @dev Calculates spot price as (x / Wx) / (y / Wy) where x is token balance, Wx is token weight,
     *      y is reference token balance, and Wy is reference token weight
     * @param tokenAddress_ The address of the token to update
     * @param tokenIndex_ The index of the token in the pool
     * @param tokenWeight_ The normalized weight of the token in the pool
     * @param lastBalancesWad_ Array of token balances in the pool
     * @param denominator_ The denominator value calculated from reference token
     */
    function _updatePrice(
        address tokenAddress_,
        uint256 tokenIndex_,
        uint256 tokenWeight_,
        uint256[] memory lastBalancesWad_,
        uint256 denominator_
    ) internal {
        Observation[] storage tokenToObservation = tokenToObservations[tokenAddress_];
        Observation storage lastObservation = tokenToObservation[tokenToObservation.length - 1];

        uint256 numerator_ = lastBalancesWad_[tokenIndex_].divWadDown(tokenWeight_);
        uint256 lastPrice_ = numerator_.divWadDown(denominator_);

        // Update observations with the last accumulatedPrice of a new block.
        // So we have maximum 1 observation per block.
        if (tokenToData[tokenAddress_].lastBlockNumber != block.number) {
            int256 nextAccumulatedPrice_ =
                _calculateAccumulatedPrice(lastObservation, block.timestamp);

            tokenToObservation.push(
                Observation({
                    timestamp: uint40(block.timestamp),
                    price: lastPrice_.safeCastTo216(),
                    accumulatedPrice: nextAccumulatedPrice_
                })
            );

            tokenToData[tokenAddress_].lastBlockNumber = uint248(block.number);
        } else {
            Observation storage secondLastObservation =
                tokenToObservation[tokenToObservation.length - 2];
            lastObservation.accumulatedPrice =
                _calculateAccumulatedPrice(secondLastObservation, block.timestamp);
            lastObservation.price = lastPrice_.safeCastTo216();
            // We don't need to update the timestamp because it stays the same within the same block.
        }

        emit GeomeanOracleHookContractPriceUpdated(tokenAddress_, lastPrice_);
    }

    /**
     * @notice Performs a binary search to find the observation closest to the target timestamp
     * @dev Uses a hint to optimize the search by starting from a specific index
     * @param observations The array of observations to search through
     * @param targetTimestamp_ The timestamp to search for
     * @param hintLow_ A hint for where to start the search (optimization). 0 if you don't have a hint.
     * @return The index of the observation closest to but not exceeding the target timestamp
     */
    function _binarySearch(
        Observation[] storage observations,
        uint256 targetTimestamp_,
        uint256 hintLow_ // TODO what happens if hintLow_ is too high? should revert
    ) internal view returns (uint256) {
        uint256 lastIndex_ = observations.length - 1;

        if (observations.length == 0 || targetTimestamp_ <= observations[0].timestamp) {
            revert GeomeanOracleHookContract__NOT_ENOUGH_OBSERVATIONS(lastIndex_ + 1);
        }

        // If target timestamp is after the latest observation, return the latest.
        if (targetTimestamp_ >= observations[lastIndex_].timestamp) {
            return lastIndex_;
        }

        // Binary search to find the closest observation.
        uint256 low_ = hintLow_; // Hint low allows to skip the first part of the array. 0 if you don't have a hint.
        uint256 high_ = lastIndex_;

        while (low_ < high_) {
            uint256 mid_ = (low_ + high_) / 2;

            if (observations[mid_].timestamp == targetTimestamp_) {
                return mid_; // Exact match
            } else if (observations[mid_].timestamp < targetTimestamp_) {
                low_ = mid_ + 1;
            } else {
                high_ = mid_;
            }
        }

        // At this point, low == high_
        // If the timestamp at low is greater than target, we need the previous observation.
        if (observations[low_].timestamp > targetTimestamp_) {
            return low_ - 1;
        }

        return low_;
    }
}
