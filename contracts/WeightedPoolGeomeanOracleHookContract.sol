// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

// Base imports.
import {IVault} from "lib/balancer-v3-monorepo/pkg/interfaces/contracts/vault/IVault.sol";
import {BaseGeomeanOracleHookContract} from "contracts/base/BaseGeomeanOracleHookContract.sol";
import {FixedPointMathLib} from "lib/solmate/src/utils/FixedPointMathLib.sol";

// WeightedPool imports.
import {WeightedPool} from "lib/balancer-v3-monorepo/pkg/pool-weighted/contracts/WeightedPool.sol";

contract WeightedPoolGeomeanOracleHookContract is BaseGeomeanOracleHookContract {
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
        uint256[] memory indexToWeight_ = WeightedPool(pool).getNormalizedWeights();
        uint256 referenceTokenIndex_ = tokenToData[referenceToken].index;
        uint256 tokenIndex_ = tokenToData[_token].index;

        /////////////////////////////////////////////////////////
        //                                            x        //
        // x = token x price                        -----      //
        // Wx = token x weight                        Wx       //
        // y = token y price         Spot price = ---------    //
        // Wy = token y weight                        y        //
        //                                          -----      //
        //                                            Wy       //
        /////////////////////////////////////////////////////////

        uint256 numerator_ =
            _lastBalancesWad[referenceTokenIndex_].divWadDown(indexToWeight_[referenceTokenIndex_]);
        uint256 denominator_ = _lastBalancesWad[tokenIndex_].divWadDown(indexToWeight_[tokenIndex_]);

        return numerator_.divWadDown(denominator_);
    }
}
