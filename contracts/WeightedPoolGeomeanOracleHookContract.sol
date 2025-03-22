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

contract WeightedPoolGeomeanOracleHookContract is BaseHooks, VaultGuard {
    using FixedPointMathLib for uint256;

    struct Observation {
        uint256 timestamp;
        uint256 price;
        int256 accumulatedPrice;
    }

    // TODO merge all these into a single mapping => gas optimized struct
    mapping(address => uint256) public tokenToWeight;
    mapping(address => uint256) public tokenToIndex;
    mapping(address => Observation[]) public tokenToObservations;
    mapping(address => uint256) public tokenToLastBlockNumber;
    mapping(address => uint256) public tokenToLastTimestamp;
    mapping(address => int256) public tokenToLastAccumulatedPrice;

    address[] public tokensSorted;
    address public immutable allowedFactory;
    address public immutable referenceToken;
    address public immutable vault;
    address public pool;

    /// Events
    event WeightedPoolGeomeanOracleHookContractRegistered(
        address indexed hook, address indexed pool
    );

    /// Errors
    error WeightedPoolGeomeanOracleHookContract__REFERENCE_TOKEN_NOT_SUPPORTED();
    error WeightedPoolGeomeanOracleHookContract__ALREADY_REGISTERED();
    error WeightedPoolGeomeanOracleHookContract__FACTORY_NOT_ALLOWED(address factory);
    error WeightedPoolGeomeanOracleHookContract__POOL_NOT_FROM_FACTORY(address pool);
    error WeightedPoolGeomeanOracleHookContract__TOKEN_NOT_INCLUDED();
    error WeightedPoolGeomeanOracleHookContract__NOT_ENOUGH_OBSERVATIONS(
        uint256 numberOfObservations
    );

    /**
     * @notice Initializes the oracle hook contract.
     * @param _vault The address of the Balancer V3 Vault.
     * @param _allowedFactory The address of the WeightedPool factory that is allowed to create pools with this hook.
     * @param _tokensSorted The addresses of the tokens in the pool in the correct order.
     * @param _referenceToken The address of the token to use as reference for price calculations.
     */
    constructor(
        address _vault,
        address _allowedFactory,
        address[] memory _tokensSorted,
        address _referenceToken
    ) VaultGuard(IVault(_vault)) {
        // Check if reference token is included in the pool.
        bool isReferenceTokenIncluded_;
        for (uint256 i; i < _tokensSorted.length; i++) {
            if (_tokensSorted[i] == _referenceToken) {
                isReferenceTokenIncluded_ = true;
            }
        }
        if (!isReferenceTokenIncluded_) {
            revert WeightedPoolGeomeanOracleHookContract__REFERENCE_TOKEN_NOT_SUPPORTED();
        }

        vault = _vault;
        allowedFactory = _allowedFactory;
        referenceToken = _referenceToken;
        tokensSorted = _tokensSorted;
    }

    /// @inheritdoc BaseHooks
    function onRegister(
        address _factory,
        address _pool,
        TokenConfig[] memory _tokenConfigs,
        LiquidityManagement calldata
    ) public override onlyVault returns (bool) {
        if (pool != address(0)) {
            revert WeightedPoolGeomeanOracleHookContract__ALREADY_REGISTERED();
        }
        pool = _pool;

        // Check if factory is allowed.
        if (_factory != allowedFactory) {
            revert WeightedPoolGeomeanOracleHookContract__FACTORY_NOT_ALLOWED(_factory);
        }

        // Check if pool was created by the allowed factory.
        if (!BasePoolFactory(_factory).isPoolFromFactory(_pool)) {
            revert WeightedPoolGeomeanOracleHookContract__POOL_NOT_FROM_FACTORY(_pool);
        }

        // Check if all tokens are included in the pool and in the correct order.
        for (uint256 i; i < _tokenConfigs.length; i++) {
            tokenToIndex[address(_tokenConfigs[i].token)] = i;
            if (address(_tokenConfigs[i].token) != tokensSorted[i]) {
                revert WeightedPoolGeomeanOracleHookContract__TOKEN_NOT_INCLUDED();
            }
        }

        // Initialize observations.
        // AccumulatedPrice is 0 because we don't have any price data yet.
        // The oracle will be safe once the observation period has passed.
        for (uint256 i; i < _tokenConfigs.length; i++) {
            if (address(_tokenConfigs[i].token) != referenceToken) {
                tokenToObservations[address(_tokenConfigs[i].token)].push(
                    Observation({timestamp: block.timestamp, price: 0, accumulatedPrice: 0})
                );
            }
        }

        emit WeightedPoolGeomeanOracleHookContractRegistered(address(this), _pool);

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
        // Init tokenToWeight. Can be called only once since weights doesn't change.
        if (tokenToWeight[address(params.tokenIn)] == 0) {
            // Unfortunatelly, we cannot be called in onRegister because the pool is not yet initialized. (PoolNotRegistered())
            WeightedPoolImmutableData memory poolData =
                WeightedPool(params.pool).getWeightedPoolImmutableData();
            for (uint256 i = 0; i < poolData.tokens.length; i++) {
                tokenToWeight[address(poolData.tokens[i])] = poolData.normalizedWeights[i];
            }
        }

        (,,, uint256[] memory lastBalancesWad_) = IVault(vault).getPoolTokenInfo(params.pool);

        // Spot price == x * Wy / y * Wx = (x / Wx) / (y / Wy)
        uint256 denominator_ =
            lastBalancesWad_[tokenToIndex[referenceToken]].divWadDown(tokenToWeight[referenceToken]);

        // Update prices of the tokens swapped.
        _updatePrice(address(params.tokenIn), lastBalancesWad_, denominator_);
        _updatePrice(address(params.tokenOut), lastBalancesWad_, denominator_);

        return (true, 0);
    }

    function _updatePrice(address token_, uint256[] memory lastBalancesWad_, uint256 denominator_)
        internal
    {
        if (token_ != referenceToken) {
            Observation[] storage tokenToObservation = tokenToObservations[token_];
            Observation storage lastObservation = tokenToObservation[tokenToObservation.length - 1];

            uint256 numerator_ =
                lastBalancesWad_[tokenToIndex[token_]].divWadDown(tokenToWeight[token_]);
            uint256 lastPrice_ = numerator_.divWadDown(denominator_);

            // Update observations with the last accumulatedPrice of a new block.
            // So we have maximum 1 observation per block.
            if (tokenToLastBlockNumber[token_] != block.number) {
                uint256 lastTimestamp_ = lastObservation.timestamp;
                int256 lastAccumulatedPrice_ = lastObservation.accumulatedPrice;
                int256 nextAccumulatedPrice_ = lastAccumulatedPrice_
                    + (int256(block.timestamp) - int256(lastTimestamp_)) * wadLn(int256(lastPrice_));

                tokenToObservation.push(
                    Observation({
                        timestamp: block.timestamp,
                        price: lastPrice_,
                        accumulatedPrice: nextAccumulatedPrice_
                    })
                );

                tokenToLastBlockNumber[token_] = block.number;
                tokenToLastTimestamp[token_] = lastTimestamp_;
                tokenToLastAccumulatedPrice[token_] = lastAccumulatedPrice_;
            } else {
                lastObservation.accumulatedPrice = tokenToLastAccumulatedPrice[token_]
                    + (int256(block.timestamp) - int256(tokenToLastTimestamp[token_]))
                        * wadLn(int256(lastPrice_));
                lastObservation.price = lastPrice_;
                // We don't need to update the timestamp because it stays the same within the same block.
            }

            // TODO emit event
        }
    }

    function _binarySearch(Observation[] storage observations, uint256 targetTimestamp_)
        internal
        view
        returns (uint256)
    {
        uint256 lastIndex_ = observations.length - 1;

        if (observations.length == 0 || targetTimestamp_ <= observations[0].timestamp) {
            revert WeightedPoolGeomeanOracleHookContract__NOT_ENOUGH_OBSERVATIONS(lastIndex_ + 1);
        }

        // If target timestamp is after the latest observation, return the latest
        if (targetTimestamp_ >= observations[lastIndex_].timestamp) {
            return lastIndex_;
        }

        // Binary search to find the closest observation
        uint256 low_ = 0; // TODO can be obtimized
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
        // If the timestamp at low is greater than target, we need the previous observation
        if (observations[low_].timestamp > targetTimestamp_) {
            return low_ - 1;
        }

        return low_;
    }

    // TODO
    /// @dev Geomean price = ∏(x_i^ΔT_i)^(1/n)
    //                     = exp(Σ(ΔT_i * ln(price_i)) / n)
    //
    /// @dev Geomean price over a period = exp(accumulatedPrice(timestamp - period) - accumulatedPrice(timestamp)) / observationPeriod_)
    //
    function getGeomeanPrice(address token_, uint256 observationPeriod_)
        public
        view
        returns (uint256)
    {
        Observation[] storage observations = tokenToObservations[token_];
        Observation storage observations1 = observations[observations.length - 1];
        uint256 startPeriodTimestamp_ = block.timestamp - observationPeriod_;
        Observation storage observations2 =
            observations[_binarySearch(observations, startPeriodTimestamp_)];

        int256 apNow_ = observations1.accumulatedPrice
            + (int256(block.timestamp) - int256(observations1.timestamp))
                * wadLn(int256(observations1.price));

        int256 apPeriod_ = observations2.accumulatedPrice
            + (int256(startPeriodTimestamp_) - int256(observations2.timestamp))
                * wadLn(int256(observations2.price));

        console2.log("cpNow_    ::: %18e", apNow_);
        console2.log("cpPeriod_ ::: %18e", apPeriod_);
        console2.log("observationPeriod_Theorical ::: ", int256(startPeriodTimestamp_));
        console2.log("observationPeriod_Real      ::: ", int256(observations2.timestamp));

        int256 numerator_ = apNow_ - apPeriod_;

        return uint256(wadExp(numerator_ / int256(observationPeriod_)));
    }

    /**
     * @notice Get the price of the pool.
     * @return price The price of the pool in units of the reference token.
     */
    function getPrice(address token) public view returns (uint256) {
        return tokenToObservations[token][tokenToObservations[token].length - 1].price; // TODO: scale to reference token decimals
    }
}
