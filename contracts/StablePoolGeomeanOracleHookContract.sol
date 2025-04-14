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
    function _calculateTokenPrice(address _token, uint256[] memory _lastBalancesWad)
        internal
        view
        override
        returns (uint256)
    {
        uint256 numerator_ =
            _calculatePartialDerivative(_lastBalancesWad, tokenToData[_token].index);
        uint256 denominator_ =
            _calculatePartialDerivative(_lastBalancesWad, tokenToData[referenceToken].index);

        return numerator_.divWadDown(denominator_);
    }

    /**
     * @notice Calculates the partial derivative of the invariant function with respect to a token.
     * @dev This function is implemented by derived contracts based on their specific pool math.
     * @param _lastBalancesWad The array of token balances in WAD format.
     * @param _tokenIndex The index of the token in the pool.
     * @return The partial derivative value used in price calculations.
     */
    function _calculatePartialDerivative(uint256[] memory _lastBalancesWad, uint256 _tokenIndex)
        internal
        view
        returns (uint256)
    {
        StablePool pool_ = StablePool(pool);

        /////////////////////////////////////////////////////////////////////////////////////////////////////////
        // S = sum of all balances                                                                             //
        // D = invariant                              df            D^(n+1)           1                        //
        // A = amplification coefficient (n^n * A)  ------ = A + ------------- = A + --- * (A * S + D - A * D) //
        // P = product of balances                    dx          n^n * x * P         x                        //
        // n = number of tokens                                                                                //
        /////////////////////////////////////////////////////////////////////////////////////////////////////////

        uint256 n_ = _lastBalancesWad.length;
        (uint256 a_,, uint256 AMP_PRECISION) = pool_.getAmplificationParameter();
        uint256 D_ = pool_.computeInvariant(_lastBalancesWad, Rounding.ROUND_UP);
        uint256 A_ = n_ * a_;
        uint256 S_;
        for (uint256 i = 0; i < _lastBalancesWad.length; i++) {
            S_ = S_ + _lastBalancesWad[i];
        }

        return A_ * WAD / AMP_PRECISION
            + (A_ * S_ / AMP_PRECISION + D_ - A_ * D_ / AMP_PRECISION).divWadDown(
                _lastBalancesWad[_tokenIndex]
            );
    }
}
