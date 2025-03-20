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

contract WeightedPoolGeomeanOracleHookContract is BaseHooks, VaultGuard {
    using FixedPointMathLib for uint256;

    mapping(address => uint256) public tokenToWeight;
    mapping(address => uint256) public tokenToIndex;
    mapping(address => uint256) public prices;
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
        prices[referenceToken] = 10 ** ERC20(_referenceToken).decimals();
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

        (,, uint256[] memory lastBalancesRaw_,) = IVault(vault).getPoolTokenInfo(params.pool);

        // Spot price == x * Wy / y * Wx
        uint256 weightReferenceToken_ = tokenToWeight[address(referenceToken)];
        uint256 denominator_ = lastBalancesRaw_[tokenToIndex[address(referenceToken)]].mulWadDown(
            tokenToWeight[address(params.tokenIn)]
        );

        if (address(params.tokenIn) != referenceToken) {
            uint256 numerator1_ = lastBalancesRaw_[tokenToIndex[address(params.tokenIn)]].mulWadDown(
                weightReferenceToken_
            );
            prices[address(params.tokenIn)] = numerator1_ * prices[referenceToken] / denominator_;
        }
        if (address(params.tokenOut) != referenceToken) {
            uint256 numerator2_ = lastBalancesRaw_[tokenToIndex[address(params.tokenOut)]].mulWadDown(
                weightReferenceToken_
            );
            prices[address(params.tokenOut)] = numerator2_ * prices[referenceToken] / denominator_;
        }

        return (true, 0);
    }

    /**
     * @notice Get the price of the pool.
     * @return price The price of the pool in units of the reference token.
     */
    function getPrice(address token) public view returns (uint256) {
        return prices[token];
    }
}
