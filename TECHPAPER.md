# Balancer V3 Geomean oracle (WIP)

## Abstract

The Balancer V3 Geomean Oracle is a robust price oracle solution designed specifically for Balancer V3 pools. It provides reliable, manipulation-resistant price data for assets by calculating geometric mean prices over customizable time periods. Implemented as hook contracts for both Weighted and Stable pools, the oracle updates on every swap and features block-level granularity with built-in safeguards against price manipulation. The system requires zero maintenance after deployment and supports seamless integration with the broader DeFi ecosystem through an optional Chainlink-compatible adaptor.

## Specs

- **Compatibility**: Works with Weighted pools (any number of assets, any weight) and Stable pools (any number of assets).
- **Update Frequency**: On every swap.
- **Granularity**: One price update per block maximum.
- **Manipulation Resistance**:
  - Inherently protected against single-block manipulation via geometric mean calculation.
  - **Manipulation Safe Guard**: Implements a maximum price change limit of 10% per block. This relies on the assumption that larger changes are likely manipulation or highly inefficient swaps.
  - **Worst-Case Scenario**: Even if an attacker controls 16 consecutive blocks on Ethereum mainnet (an extremely unlikely event), the maximum price deviation is calculated to be 8.5% over a 1-hour observation period.
- **Flexibility**:
  - Fully customizable observation period (up to 30 days).
  - Ability to create multiple Chainlink adaptors from a single oracle hook contract.
- **Maintenance**: Zero maintenance required after initial deployment.
- **Price Transformation**: Chainlink adaptors can be configured with a `_chainlinkAggregator` to convert the price output from the reference token denomination to another (e.g., from USDC to USD), enhancing interoperability.
- **Security Profile**: Depending on the underlying blockchain's security and block times, this oracle can be considered safer than many second-class oracles.

## The maths

### Geometric mean

The geometric mean price provides a time-weighted average that naturally resists short-term price manipulation. It is calculated as:

$$\text{Geometric Mean Price} = \left( \prod_{i} price_i^{\Delta T_i} \right)^{1/T}$$

Where:
- $price_i$ is the spot price during the $i$-th interval.
- $\Delta T_i$ is the duration of the $i$-th interval.
- $T = \sum \Delta T_i$ is the total observation period.

For computational efficiency and to avoid precision issues with products of many numbers, the oracle uses the logarithmic form:

$$\text{Geometric Mean Price} = \exp\left(\frac{\sum_{i} (\Delta T_i \cdot \ln(price_i))}{T}\right)$$

The term $\sum_{i} (\Delta T_i \cdot \ln(price_i))$ represents the accumulated log-price over the period $T$.

### Weighted Pool

In Balancer V3 Weighted Pools, the spot price between two tokens (A and B) is determined by their balances ($balance_A$, $balance_B$) and their normalized weights ($weight_A$, $weight_B$):

$$\text{Spot Price} = \frac{b_B / w_B}{b_A / w_A}$$

Where:
- $b_A$ is the balance of token A
- $b_B$ is the balance of token B
- $w_A$ is the weight of token A
- $w_B$ is the weight of token B


This price reflects the marginal rate of substitution between the assets in the pool and is used as the $price_i$ input for the geometric mean calculation.

### Stable Pool

For Balancer V3 Stable Pools, the price calculation involves the pool's invariant $f$ and requires calculating partial derivatives with respect to the balances of the involved tokens ($x$ for the token, $y$ for the reference token):

$$\text{Spot Price} = \frac{\partial f / \partial y}{\partial f / \partial x}$$

The specific form of the partial derivative for a token $x$ in a Stable Pool is:

$$\frac{\partial f}{\partial x} = A + \frac{D^{(n+1)}}{n^n \cdot x \cdot P} = A + \frac{1}{x} \cdot (A \cdot S + D - A \cdot D)$$

Where:
- $S$ is the sum of all token balances (scaled).
- $D$ is the pool's invariant.
- $A$ is the amplification parameter (related to the `amp` factor).
- $P$ is the product of all token balances (scaled).
- $n$ is the number of tokens in the pool.

This spot price is then used as the $price_i$ input for the geometric mean calculation.

## How does it work

### Observation

The oracle stores price observations for each non-reference token within the pool. Each observation captures the state at a specific point in time:

```solidity
struct Observation {
    uint40 timestamp;         // Timestamp of the observation
    uint216 scaled18Price;    // Spot price at timestamp (scaled to 18 decimals)
    int256 accumulatedPrice;  // Accumulated log-price (ln(price) * time) up to timestamp
}
```

Observations are recorded with a maximum frequency of one per block. If multiple swaps occur within the same block, only the price resulting from the *last* swap in that block is recorded or used to update the existing observation for that block. This prevents intra-block manipulation from affecting the oracle state more than once per block.

### Price updates

Price updates are triggered by the `onAfterSwap` hook, which is called by the Balancer Vault after each swap involving the pool. The update logic is as follows:

1.  **Calculate Current Spot Price**: Determine the spot price based on the pool's balances after the swap (using the formulas described in "The maths" section).
2.  **Check Block Number**: Compare the current `block.number` with the `lastBlockNumber` stored for the token.
3.  **New Block**:
    - Retrieve the `scaled18Price` from the *most recent* stored observation.
    - Apply the `_manipulationSafeGuard` to the newly calculated spot price, comparing it against the retrieved last price. This clamps the change to +/- 10%.
    - Calculate the `accumulatedPrice` up to the current `block.timestamp` based on the *previous* observation's state.
    - Store a *new* `Observation` struct with the current `block.timestamp`, the manipulation-checked `scaled18Price`, and the calculated `accumulatedPrice`.
    - Update the token's `lastBlockNumber` to the current `block.number`.
4.  **Same Block**:
    - Retrieve the `scaled18Price` from the *second-to-last* stored observation (the price before the first swap in this block).
    - Apply the `_manipulationSafeGuard` to the newly calculated spot price, comparing it against the retrieved second-to-last price.
    - Recalculate the `accumulatedPrice` for the *current* observation based on the state of the *second-to-last* observation and the current `block.timestamp`.
    - Update the *existing* `Observation` for the current block with the new manipulation-checked `scaled18Price` and the recalculated `accumulatedPrice`. (Timestamp remains unchanged).

The `_manipulationSafeGuard` function limits price volatility between consecutive blocks:
```solidity
function _manipulationSafeGuard(uint256 _currentPrice, uint256 _lastPrice) internal pure returns (uint256) {
    uint256 minPrice_ = _lastPrice.mulWadDown(WAD - MAX_INTER_OBSERVATION_PRICE_CHANGE); // 90% of last price
    uint256 maxPrice_ = _lastPrice.mulWadDown(WAD + MAX_INTER_OBSERVATION_PRICE_CHANGE); // 110% of last price

    if (_currentPrice > maxPrice_) {
        return maxPrice_;
    } else if (_currentPrice < minPrice_) {
        return minPrice_;
    }
    return _currentPrice; // Price change is within +/- 10%
}
```

### Geometric mean price calculation

To get the geometric mean price over a specific `_observationPeriod`, the `getGeomeanPrice` function performs these steps:

1.  **Identify Boundaries**:
    - Find the most recent observation (`observationsNow`).
    - Determine the target timestamp for the start of the period: `startPeriodTimestamp_ = block.timestamp - _observationPeriod`.
    - Use binary search (`_binarySearch`) to find the latest observation whose timestamp is less than or equal to `startPeriodTimestamp_` (`observationsPeriodStart`). A hint (`_hintLow`) can optimize this search.
2.  **Calculate Accumulated Prices**:
    - Calculate the interpolated `accumulatedPrice` at the exact current `block.timestamp` based on `observationsNow`.
    - Calculate the interpolated `accumulatedPrice` at the exact `startPeriodTimestamp_` based on `observationsPeriodStart`.
3.  **Compute Average Log-Price**: Calculate the difference between the two accumulated prices and divide by the `_observationPeriod`:
    `averageLogPrice = (accumulatedNow - accumulatedStart) / _observationPeriod`
4.  **Exponentiate**: Calculate the final geometric mean price by taking the exponent of the average log-price:
    `geomeanPrice = exp(averageLogPrice)` (using `wadExp` for fixed-point math).
5.  **Unscale**: Adjust the 18-decimal result to match the `referenceToken`'s decimals using `_unscalePrice`.

```solidity
function getGeomeanPrice(address _token, uint256 _observationPeriod, uint256 _hintLow) public view returns (uint256) {
    // ... find observationsNow and observationsPeriodStart ...

    int256 averageLogPrice_ = _calculateAccumulatedPrice(observationsNow, block.timestamp)
        - _calculateAccumulatedPrice(observationsPeriodStart, startPeriodTimestamp_);

    return _unscalePrice(uint256(wadExp(averageLogPrice_ / int256(_observationPeriod))));
}

function _calculateAccumulatedPrice(Observation storage observation, uint256 _timestamp) internal view returns (int256) {
    // Interpolates accumulated price to _timestamp based on the observation's state
    return observation.accumulatedPrice + (int256(_timestamp - observation.timestamp)) * wadLn(int216(observation.scaled18Price));
}
```

## Chainlink adaptor

The `ChainlinkPriceFeedAdaptor` contract provides an interface compatible with Chainlink's `AggregatorV2V3Interface`. This allows seamless integration with protocols and systems that expect Chainlink price feeds.

**Key Features**:

- Implements standard Chainlink methods like `latestAnswer()`, `latestTimestamp()`, `latestRoundData()`, `decimals()`, `description()`, etc.
- Fetches the geometric mean price from the underlying `GeomeanOracleHookContract` for the specified `observationPeriod`.
- **Optional Price Conversion**: If a `_chainlinkAggregator` address (pointing to an existing Chainlink feed, e.g., USDC/USD) is provided during adaptor creation, the adaptor will automatically convert the oracle's output price.
    - Example: If the oracle provides ETH/USDC and the `_chainlinkAggregator` is USDC/USD, the adaptor's `latestAnswer()` will return the price in ETH/USD.
    - Conversion logic: `finalPrice = (oraclePrice_ETH_USDC * chainlinkPrice_USDC_USD) / 10^referenceTokenDecimals`
- **Simplified Round IDs**: Since the oracle updates continuously, the adaptor often uses `block.timestamp` as a proxy for round IDs where applicable, unless a real `_chainlinkAggregator` is used, in which case it delegates round information.

**Creation**: Adaptors are deployed via the hook contract:
```solidity
function createChainlinkPriceFeedAdaptor(
    address _token,                 // Token to get price for
    uint256 _observationPeriod,     // TWAP period for this adaptor
    address _chainlinkAggregator    // Optional: Address of Chainlink feed for price conversion (e.g., USDC/USD)
) external returns (address);       // Returns address of the new adaptor
```
This allows creating multiple adaptors with different observation periods or target denominations from the same core oracle hook.

## Conclusion

The Balancer V3 Geomean Oracle offers a highly robust, flexible, and low-maintenance on-chain price feed solution. Its use of geometric means and per-block manipulation safeguards provides strong resistance against common oracle attacks. Compatibility with both Weighted and Stable pools, coupled with the Chainlink adaptor for enhanced interoperability, makes it a versatile tool for DeFi applications built on Balancer V3. The zero-maintenance design further reduces operational overhead for developers. Its security properties, particularly the quantifiable resistance to multi-block manipulation, position it as a potentially safer alternative to simpler TWAP oracles or less established price sources, especially on blockchains with reliable block production.
