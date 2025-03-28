// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { PoolRoleAccounts } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { ERC20TestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/ERC20TestToken.sol";
import { E2eBatchSwapTest } from "@balancer-labs/v3-vault/test/foundry/E2eBatchSwap.t.sol";

import { StablePoolContractsDeployer } from "./utils/StablePoolContractsDeployer.sol";
import { StablePoolFactory } from "../../contracts/StablePoolFactory.sol";
import { StablePool } from "../../contracts/StablePool.sol";

contract E2eBatchSwapStableTest is E2eBatchSwapTest, StablePoolContractsDeployer {
    using CastingHelpers for address[];

    string internal constant POOL_VERSION = "Pool v1";
    uint256 internal constant DEFAULT_SWAP_FEE_STABLE = 1e12; // 0.0001%
    uint256 internal constant DEFAULT_AMP_FACTOR = 200;

    function _setUpVariables() internal override {
        tokenA = dai;
        tokenB = usdc;
        tokenC = ERC20TestToken(address(weth));
        tokenD = wsteth;
        sender = lp;
        poolCreator = lp;

        // If there are swap fees, the amountCalculated may be lower than MIN_TRADE_AMOUNT. So, multiplying
        // MIN_TRADE_AMOUNT by 10 creates a margin.
        minSwapAmountTokenA = 10 * PRODUCTION_MIN_TRADE_AMOUNT;
        minSwapAmountTokenD = 10 * PRODUCTION_MIN_TRADE_AMOUNT;

        // 25% of pool init amount, so MIN and MAX invariant ratios are not violated.
        maxSwapAmountTokenA = poolInitAmount / 4;
        maxSwapAmountTokenD = poolInitAmount / 4;
    }

    function createPoolFactory() internal override returns (address) {
        return address(deployStablePoolFactory(IVault(address(vault)), 365 days, "Factory v1", POOL_VERSION));
    }

    /// @notice Overrides BaseVaultTest _createPool(). This pool is used by E2eBatchSwapTest tests.
    function _createPool(
        address[] memory tokens,
        string memory label
    ) internal override returns (address newPool, bytes memory poolArgs) {
        string memory name = "Stable Pool";
        string memory symbol = "STABLE";

        PoolRoleAccounts memory roleAccounts;

        bytes32 salt = keccak256(abi.encode(label));
        newPool = StablePoolFactory(poolFactory).create(
            name,
            symbol,
            vault.buildTokenConfig(tokens.asIERC20()),
            DEFAULT_AMP_FACTOR,
            roleAccounts,
            DEFAULT_SWAP_FEE_STABLE,
            address(0),
            false, // Do not enable donations
            false, // Do not disable unbalanced add/remove liquidity
            salt
        );
        vm.label(address(newPool), label);

        // Cannot set pool creator directly with stable pool factory.
        vault.manualSetPoolCreator(address(newPool), lp);

        poolArgs = abi.encode(
            StablePool.NewPoolParams({
                name: name,
                symbol: symbol,
                amplificationParameter: DEFAULT_AMP_FACTOR,
                version: POOL_VERSION
            }),
            vault
        );
    }
}
