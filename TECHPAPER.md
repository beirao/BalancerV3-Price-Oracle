# Balancer V3 Geomean oracle (WIP)

## Abstract

The Balancer V3 Geomean Oracle is a robust price oracle solution designed specifically for Balancer V3 pools. It provides reliable, manipulation-resistant price data for assets by calculating geometric mean prices over customizable time periods. Implemented as hook contracts for both Weighted and Stable pools, the oracle updates on every swap and features block-level granularity with built-in safeguards against price manipulation. The system supports seamless integration with the broader DeFi ecosystem through an optional Chainlink-compatible adaptor.

## Specs

- **Compatibility**: Works with Weighted pools and Stable pools containing any number of assets
- **Update Frequency**: On every swap
- **Granularity**: One price update per block maximum
- **Manipulation Resistance**:
  - Protected against single-block manipulation through geometric mean calculation
  - 10% maximum price change limit per block
  - Even with control of 16 consecutive blocks, price deviation is limited to 8.5% over a 1-hour period
- **Flexibility**: 
  - Customizable observation period (up to 30 days)
  - Create multiple Chainlink adaptors from a single oracle
- **Maintenance**: Zero maintenance required after deployment
- **Transformation**: Chainlink adaptors allow converting prices between different denominations (e.g., USDC to USD)

## The maths

### Geometric mean

The geometric mean price is calculated as follows:

$$\text{Geometric Mean Price} = \prod_{i} (price_i^{\Delta T_i})^{1/T}$$

Where:
- $price_i$ represents the price at each observation point
- $\Delta T_i$ is the time interval for that observation
- $T$ is the total observation period

For computational efficiency, this is implemented as:

$$\text{Geometric Mean Price} = \exp\left(\frac{\sum_{i} (\Delta T_i \cdot \ln(price_i))}{T}\right)$$

This approach provides a time-weighted average that is resistant to short-term price spikes and manipulation attempts.

### Weighted Pool

For Weighted pools, the spot price calculation uses the ratio of token balances adjusted by their respective weights:

$$\text{Spot Price} = \frac{balance_B / weight_B}{balance_A / weight_A}$$

This formula reflects the fundamental price relationship in constant-product weighted pools. The geometric mean is then calculated using these spot prices over time.

### Stable Pool

For Stable pools, the price calculation is more complex due to the invariant function for stable swaps:

The partial derivative method is used to determine spot prices:

$$\text{Spot Price} = \frac{\partial f / \partial y}{\partial f / \partial x}$$

Where:
- $f$ is the invariant function
- $x$ is the token balance
- $y$ is the reference token balance

For stable pools specifically:

$$\frac{\partial f}{\partial x} = A + \frac{D^{(n+1)}}{n^n \cdot x \cdot P} = A + \frac{1}{x} \cdot (A \cdot S + D - A \cdot D)$$

Where:
- $S$ is the sum of all balances
- $D$ is the invariant
- $A$ is the amplification coefficient
- $P$ is the product of balances
- $n$ is the number of tokens

## How does it work

### Observation

The oracle maintains an array of price observations for each token in the pool:

```solidity
struct Observation {
    uint40 timestamp;
    uint216 scaled18Price;
    int256 accumulatedPrice;
}
```

Each observation includes:
- The timestamp when the observation was recorded
- The price at that time (scaled to 18 decimals)
- The accumulated price used for TWAP calculations

The observations are recorded on a per-block basis, with a maximum of one observation per block to prevent manipulation within a single block.

### Price updates

Price updates occur after every swap transaction through the `onAfterSwap` hook. The process follows these steps:

1. Calculate the spot price based on the current pool state
2. If this is a new block since the last update:
   - Apply the manipulation safeguard (limit price changes to 10%)
   - Create a new observation with the current timestamp, price, and accumulated price
3. If this is the same block as the last update:
   - Update the existing observation with the new price
   - The manipulation safeguard is still applied

The manipulation safeguard works by comparing the current price to the previous price:
```solidity
function _manipulationSafeGuard(uint256 _currentPrice, uint256 _lastPrice) internal pure returns (uint256) {
    uint256 minPrice_ = _lastPrice.mulWadDown(WAD - MAX_INTER_OBSERVATION_PRICE_CHANGE);
    uint256 maxPrice_ = _lastPrice.mulWadDown(WAD + MAX_INTER_OBSERVATION_PRICE_CHANGE);

    if (_currentPrice > maxPrice_) {
        return maxPrice_;
    } else if (_currentPrice < minPrice_) {
        return minPrice_;
    }
    return _currentPrice;
}
```

### Geometric mean price calculation

The geometric mean price over a specified observation period is calculated as follows:

1. Find the observation at the start of the period using binary search
2. Calculate the accumulated price at the current time
3. Calculate the accumulated price at the start of the period
4. Compute the difference and divide by the observation period
5. Apply the exponential function to get the geometric mean price

```solidity
function getGeomeanPrice(address _token, uint256 _observationPeriod, uint256 _hintLow) public view returns (uint256) {
    // ...
    int256 numerator_ = _calculateAccumulatedPrice(observationsNow, block.timestamp)
        - _calculateAccumulatedPrice(observationsPeriodStart, startPeriodTimestamp_);

    return _unscalePrice(uint256(wadExp(numerator_ / int256(_observationPeriod))));
}
```

The use of the geometric mean ensures that the price is resistant to short-term manipulation, as it requires sustained price movement over the entire observation period to significantly impact the reported price.

## Chainlink adaptor

The Chainlink adaptor (ChainlinkPriceFeedAdaptor) provides compatibility with systems that expect Chainlink's AggregatorV2V3 interface. Key features include:

- Implements standard Chainlink interface methods (`latestAnswer()`, `latestRoundData()`, etc.)
- Maps the geometric mean price to Chainlink's price representation
- Allows for optional price conversion through an external Chainlink feed
- Can transform prices from one denomination to another (e.g., from USDC to USD)

Creation of a new adaptor is simple:
```solidity
function createChainlinkPriceFeedAdaptor(
    address _token,
    uint256 _observationPeriod,
    address _chainlinkAggregator
) external returns (address)
```

The adaptor is particularly useful for:
- Integrating with systems that require Chainlink price feeds
- Converting between different price denominations
- Providing compatibility with existing DeFi protocols

## Conclusion

The Balancer V3 Geomean Oracle provides a robust, flexible, and manipulation-resistant price oracle solution for DeFi applications. By leveraging the geometric mean calculation and implementing strong safeguards against price manipulation, the oracle ensures reliable price data even in adversarial conditions.

Key advantages include:
- Zero maintenance requirements
- Strong protection against manipulation (maximum 8.5% deviation even in extreme scenarios)
- Flexibility in observation periods and price denominations
- Seamless integration with existing DeFi infrastructure through Chainlink compatibility

The combination of mathematical robustness, security features, and integration capabilities makes this oracle solution appropriate for a wide range of DeFi applications requiring reliable price data from Balancer V3 pools.
