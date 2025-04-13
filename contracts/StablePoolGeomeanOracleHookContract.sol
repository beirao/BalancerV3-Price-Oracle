// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

// Base imports.
import {IVault} from "lib/balancer-v3-monorepo/pkg/interfaces/contracts/vault/IVault.sol";
import {BaseGeomeanOracleHookContract} from "contracts/base/BaseGeomeanOracleHookContract.sol";
import {FixedPointMathLib} from "lib/solmate/src/utils/FixedPointMathLib.sol";

// StablePool imports.
import {
    StablePool, Rounding
} from "lib/balancer-v3-monorepo/pkg/pool-stable/contracts/StablePool.sol";

contract StablePoolGeomeanOracleHookContract is BaseGeomeanOracleHookContract {
    using FixedPointMathLib for uint256;

    /**
     * @notice Initializes the oracle hook contract.
     * @param _vault The address of the Balancer V3 Vault.
     * @param _referenceToken The address of the token to use as reference for price calculations.
     */
    constructor(address _vault, address _referenceToken)
        BaseGeomeanOracleHookContract(_vault, _referenceToken)
    {}

    /// @inheritdoc BaseGeomeanOracleHookContract
    function getLastPrice(address _token) public view override returns (uint256) {
        (,,, uint256[] memory lastBalancesWad_) = IVault(vault).getPoolTokenInfo(pool);

        uint256 numerator_ =
            _calculatePartialDerivative(lastBalancesWad_, tokenToData[_token].index, 0);
        uint256 denominator_ =
            _calculatePartialDerivative(lastBalancesWad_, tokenToData[referenceToken].index, 0);

        return _unscalePrice(numerator_.divWadDown(denominator_));
    }

    /// @inheritdoc BaseGeomeanOracleHookContract
    function _calculatePartialDerivative(
        uint256[] memory lastBalancesWad_,
        uint256 tokenIndex_,
        uint256
    ) internal view override returns (uint256) {
        StablePool pool_ = StablePool(pool);

        /////////////////////////////////////////////////////////////////////////////////////////////////////////
        // S = sum of all balances                                                                             //
        // D = invariant                              df            D^(n+1)           1                        //
        // A = amplification coefficient (n^n * A)  ------ = A + ------------- = A + --- * (A * S + D - A * D) //
        // P = product of balances                    dx          n^n * x * P         x                        //
        // n = number of tokens                                                                                //
        /////////////////////////////////////////////////////////////////////////////////////////////////////////

        uint256 n_ = lastBalancesWad_.length;
        (uint256 a_,, uint256 AMP_PRECISION) = pool_.getAmplificationParameter();
        uint256 D_ = pool_.computeInvariant(lastBalancesWad_, Rounding.ROUND_UP);
        uint256 A_ = n_ * a_;
        uint256 S_;
        for (uint256 i = 0; i < lastBalancesWad_.length; i++) {
            S_ = S_ + lastBalancesWad_[i];
        }

        return A_ * WAD / AMP_PRECISION
            + (A_ * S_ / AMP_PRECISION + D_ - A_ * D_ / AMP_PRECISION).divWadDown(
                lastBalancesWad_[tokenIndex_]
            );
    }
}
