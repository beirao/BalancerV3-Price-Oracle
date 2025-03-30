// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "forge-std/console2.sol";

import {Test} from "forge-std/Test.sol";
import {Sort} from "./Sort.sol";
import {Constants} from "./Constants.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ERC20Mock} from "./ERC20Mock.sol";

/// balancer V3 imports
import {
    TokenConfig,
    TokenType,
    PoolRoleAccounts,
    LiquidityManagement,
    AddLiquidityKind,
    RemoveLiquidityKind,
    AddLiquidityParams,
    RemoveLiquidityParams
} from "lib/balancer-v3-monorepo/pkg/interfaces/contracts/vault/VaultTypes.sol";
// import {IVault} from "lib/balancer-v3-monorepo/pkg/interfaces/contracts/vault/IVault.sol";
import {Vault} from "lib/balancer-v3-monorepo/pkg/vault/contracts/Vault.sol";
import {StablePoolFactory} from
    "lib/balancer-v3-monorepo/pkg/pool-stable/contracts/StablePoolFactory.sol";
import {WeightedPoolFactory} from
    "lib/balancer-v3-monorepo/pkg/pool-weighted/contracts/WeightedPoolFactory.sol";
import {IRateProvider} from
    "lib/balancer-v3-monorepo/pkg/interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";
import {TRouter} from "./TRouter.sol";
import {IVaultExplorer} from
    "lib/balancer-v3-monorepo/pkg/interfaces/contracts/vault/IVaultExplorer.sol";
import {TRouter} from "./TRouter.sol";

contract TestTwapBal is Test, Sort, Constants {
    uint128 public constant INITIAL_USDT_AMT = 10_000_000e18;
    uint128 public constant INITIAL_USDC_AMT = 10_000_000e18;

    uint128 public constant INITIAL_ETH_MINT = 1000 ether;

    address public userA = address(0x1);
    address public userB = address(0x2);
    address public userC = address(0x3);
    address public owner = address(this);
    address public guardian = address(0x4);
    address public treasury = address(0x5);

    IERC20 public usdc;
    IERC20 public usdt;

    uint256 public forkIdEth;
    uint256 public forkIdPolygon;

    uint256 public virtualTimestamp;

    TRouter public router;

    uint256 public constant BLOCK_NUMBER_ETH_MAINNET = 22146768;

    function setUp() public virtual {
        string memory MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");
        forkIdEth = vm.createFork(MAINNET_RPC_URL, BLOCK_NUMBER_ETH_MAINNET);
        vm.selectFork(forkIdEth);

        virtualTimestamp = block.timestamp;

        vm.warp(virtualTimestamp / 12 * 12);
        vm.roll(virtualTimestamp / 12);

        vm.deal(userA, INITIAL_ETH_MINT);
        vm.deal(userB, INITIAL_ETH_MINT);
        vm.deal(userC, INITIAL_ETH_MINT);

        usdc = IERC20(address(new ERC20Mock{salt: "1"}(18)));
        usdt = IERC20(address(new ERC20Mock{salt: "2"}(18)));

        /// initial mint
        ERC20Mock(address(usdc)).mint(userA, INITIAL_USDC_AMT);
        ERC20Mock(address(usdt)).mint(userA, INITIAL_USDT_AMT);

        ERC20Mock(address(usdc)).mint(userB, INITIAL_USDC_AMT);
        ERC20Mock(address(usdt)).mint(userB, INITIAL_USDT_AMT);

        ERC20Mock(address(usdc)).mint(userC, INITIAL_USDC_AMT);
        ERC20Mock(address(usdt)).mint(userC, INITIAL_USDT_AMT);

        ERC20Mock(address(usdc)).mint(userB, INITIAL_USDC_AMT);
        ERC20Mock(address(usdt)).mint(userB, INITIAL_USDT_AMT);

        router = new TRouter();

        // MAX approve "vault" by all users
        for (uint160 i = 1; i <= 3; i++) {
            vm.startPrank(address(i)); // address(0x1) == address(1)
            usdc.approve(vaultV3, type(uint256).max);
            usdt.approve(vaultV3, type(uint256).max);
            usdc.approve(address(router), type(uint256).max);
            usdt.approve(address(router), type(uint256).max);
            vm.stopPrank();
        }
    }

    /// @dev simulate ethereum blocks. 12 seconds per block and block.timestamp is updated every 12 seconds
    ///      and stays the same for the duration of the block.
    function _updateTimestamp(uint256 _skip) internal {
        virtualTimestamp += _skip;
        vm.warp(virtualTimestamp / 12 * 12);
        vm.roll(virtualTimestamp / 12);
    }

    function createStablePool(
        IERC20[] memory assets,
        address poolHookContract,
        uint256 amplificationParameter,
        address admin
    ) public returns (address) {
        // sort tokens
        IERC20[] memory tokens = new IERC20[](assets.length);

        tokens = sort(assets);

        TokenConfig[] memory tokenConfigs = new TokenConfig[](assets.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            tokenConfigs[i] = TokenConfig({
                token: tokens[i],
                tokenType: TokenType.STANDARD,
                rateProvider: IRateProvider(address(0)),
                paysYieldFees: false
            });
        }
        PoolRoleAccounts memory roleAccounts;
        roleAccounts.pauseManager = admin;
        roleAccounts.swapFeeManager = admin;
        roleAccounts.poolCreator = address(0);

        address pool = address(
            StablePoolFactory(address(stablePoolFactory)).create(
                "Cod3x-USD-Pool",
                "CUP",
                tokenConfigs,
                amplificationParameter, // test only
                roleAccounts,
                1e12, // 0.001% (in WAD)
                poolHookContract,
                false,
                false,
                bytes32(keccak256(abi.encode(tokenConfigs, bytes("Cod3x-USD-Pool"), bytes("CUP"))))
            )
        );

        return (address(pool));
    }

    function createWeightedPool(IERC20[] memory assets, address poolHookContract, address admin)
        public
        returns (address)
    {
        // sort tokens
        IERC20[] memory tokens = new IERC20[](assets.length);

        tokens = sort(assets);

        TokenConfig[] memory tokenConfigs = new TokenConfig[](assets.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            tokenConfigs[i] = TokenConfig({
                token: tokens[i],
                tokenType: TokenType.STANDARD,
                rateProvider: IRateProvider(address(0)),
                paysYieldFees: false
            });
        }
        PoolRoleAccounts memory roleAccounts;
        roleAccounts.pauseManager = admin;
        roleAccounts.swapFeeManager = admin;
        roleAccounts.poolCreator = address(0);

        uint256[] memory normalizedWeights = new uint256[](assets.length);
        for (uint256 i = 0; i < assets.length; i++) {
            normalizedWeights[i] = 1e18 / assets.length;
        }

        address pool = address(
            WeightedPoolFactory(address(weightedPoolFactory)).create(
                "Cod3x-USD-Pool",
                "CUP",
                tokenConfigs,
                normalizedWeights, // test only
                roleAccounts,
                1e13, // 0.01% (in WAD)
                poolHookContract,
                false,
                false,
                bytes32(keccak256(abi.encode(tokenConfigs, bytes("Cod3x-USD-Pool"), bytes("CUP"))))
            )
        );

        return (address(pool));
    }
}
