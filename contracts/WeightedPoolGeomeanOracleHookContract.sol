// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

// Base imports.
import {IVault} from "lib/balancer-v3-monorepo/pkg/interfaces/contracts/vault/IVault.sol";
import {BaseGeomeanOracleHookContract} from "./base/BaseGeomeanOracleHookContract.sol";
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
    function getLastPrice(address _token) public view override returns (uint256) {
        uint256[] memory indexToWeight_ = WeightedPool(pool).getNormalizedWeights();
        uint256 referenceTokenIndex_ = tokenToData[referenceToken].index;
        uint256 tokenIndex_ = tokenToData[_token].index;
        (,,, uint256[] memory lastBalancesWad_) = IVault(vault).getPoolTokenInfo(pool);

        uint256 numerator_ = _calculatePartialDerivative(
            lastBalancesWad_, referenceTokenIndex_, indexToWeight_[referenceTokenIndex_]
        );
        uint256 denominator_ =
            _calculatePartialDerivative(lastBalancesWad_, tokenIndex_, indexToWeight_[tokenIndex_]);

        return _unscalePrice(numerator_.divWadDown(denominator_));
    }

    /// @inheritdoc BaseGeomeanOracleHookContract
    function _calculatePartialDerivative(
        uint256[] memory lastBalancesWad_,
        uint256 tokenIndex_,
        uint256 tokenWeight_
    ) internal view override returns (uint256) {
        return lastBalancesWad_[tokenIndex_].divWadDown(tokenWeight_);
    }
}
