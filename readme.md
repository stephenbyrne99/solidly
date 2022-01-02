# stableswap

Stable swap protocol allows low cost, near 0 slippage trades on tightly correlated assets. Gas used is ~100k. The protocol incentivizes fees instead of liquidity. Liquidity providers (LPs) are given incentives in the form of `token`, the amount received is calculated as follows;

* 40% of weekly distribution weighted on fees accrued for the protocol as a function of feeShare / totalFees
* 60% of weekly distribution weighted on votes from ve-token holders

The above is distributed to the `gauge` (see below), however LPs will earn between 40% and 100% based on their own ve-token balance.

## token

**TBD**

## ve-token

Vested Escrow (ve), this is the core voting mechanism of the system, used by `StableV1Factory` for gauge rewards and gauge voting

* Supports native delegation via `delegate_boost`
* `deposit_for` deposits on behalf of

## StableV1Pair

Stable V1 pair is the base pair, referred to as a `pool`, it holds two (2) closely correlated assets (example MIM-UST), it uses the standard UniswapV2Pair interface for UI & analytics compatability.

```
function mint(address to) external returns (uint liquidity)
function burn(address to) external returns (uint amount0, uint amount1)
function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external
```

Functions should not be referenced directly, should be interacted with via the StableV1Router

### StableV1Factory

Stable V1 factory allows for the creation of `pools` via ```function createPair(address tokenA, address tokenB) external returns (address pair)```

Anyone can create a pool permissionlessly.

### StableV1Router

Stable V1 router is a wrapper contract and the default entry point into Stable V1 pools.

```
function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint minLiquidity,
        address to,
        uint deadline
    ) external ensure(deadline) returns (uint amountA, uint amountB, uint liquidity)
	
function removeLiquidity(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) public ensure(deadline) returns (uint amountA, uint amountB)
	
function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external ensure(deadline) returns (uint[] memory amounts)	
```

## Gauge

Gauges distribute `token` rewards to StableV1Pair LPs based on voting weights as defined by `ve` voters.

Arbirary rewards can be added permissionlessly via ```function notifyRewardAmount(address token, uint amount) external```

## Bribe

Gauge bribes are natively supported by the protocol, Bribes inherit from Gauges and are automatically adjusted on votes.

Users that voted can claim their bribes via calling ```function getReward(address token) public```

### GaugeV1Factory

Gauge factory permissionlessly creates gauges for `pools` created by StableV1Factory. Further it handles voting for 60% of the incentives to `pools`.

```
function vote(address[] calldata _poolVote, uint[] calldata _weights) external
function distribute() external
```
