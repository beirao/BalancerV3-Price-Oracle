# Balancer V3 Geomean oracle contracts (WIP)

## TODOs

-   Tests BPT oracle/manipulation
-   Tests tokens with different decimals
-   Improve the doc

## Documentation

The project documentation is available in the [Technical Paper](./TECHPAPER.md), which provides detailed information about:

- The mathematical foundations of the Balancer V3 Geomean Oracle
- How the oracle works with both Weighted and Stable pools
- Price calculation formulas and implementation details
- Manipulation resistance mechanisms
- Integration options with external systems

For implementation details, refer to the source code of the oracle hook contracts and the Chainlink adaptor.

### Test


```shell
$ mv .env.example .env
$ forge test
```

## Typing conventions

### Variables

-   storage: `x`
-   memory/stack: `x_`
-   function params: `_x`
-   contracts/events/structs: `MyContract`
-   errors: `MyContract__ERROR_DESCRIPTION`
-   public/external functions: `myFunction()`
-   internal/private functions: `_myFunction()`
-   comments: "This is a comment to describe the variable `amount`."

### Nat Specs

```js
/**
 * @dev Internal function called whenever a position's state needs to be modified.
 * @param _amount Amount of poolToken to deposit/withdraw.
 * @param _relicId The NFT ID of the position being updated.
 * @param _kind Indicates whether tokens are being added to, or removed from, a pool.
 * @param _harvestTo Address to send rewards to (zero address if harvest should not be performed).
 * @return poolId_ Pool ID of the given position.
 * @return received_ Amount of reward token dispensed to `_harvestTo` on harvest.
 */
```

### Formating

Please use `forge fmt` before commiting.


