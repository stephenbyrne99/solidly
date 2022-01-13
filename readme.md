  
  
![alt text](Solidly-Logo_Dark.png)
  
  
Solidly allows low cost, near 0 slippage trades on uncorrelated or tightly correlated assets. The protocol incentivizes fees instead of liquidity. Liquidity providers (LPs) are given incentives in the form of `token`, the amount received is calculated as follows;

* 100% of weekly distribution weighted on votes from ve-token holders

The above is distributed to the `gauge` (see below), however LPs will earn between 40% and 100% based on their own ve-token balance.

LPs with 0 ve* balance, will earn a maximum of 40%.

## token

**TBD**

## ve-token

Vested Escrow (ve), this is the core voting mechanism of the system, used by `BaseV1Factory` for gauge rewards and gauge voting.

This is based off of ve(3,3) as proposed [here](https://andrecronje.medium.com/ve-3-3-44466eaa088b)

* `deposit_for` deposits on behalf of
* `emit Transfer` to allow compatibility with third party explorers
* balance is moved to `tokenId` instead of `address`
* Locks are unique as NFTs, and not on a per `address` basis

```
function balanceOfAtTime(address) external returns (uint)
```

* `balanceOfAtTime` will accumulate the total balance based on the amount of underlying NFTs (to a maximum of 1024 held tokens)

## BaseV1Pair

Base V1 pair is the base pair, referred to as a `pool`, it holds two (2) closely correlated assets (example MIM-UST) if a stable pool or two (2) uncorrelated assets (example FTM-SPELL) if not a stable pool, it uses the standard UniswapV2Pair interface for UI & analytics compatibility.

```
function mint(address to) external returns (uint liquidity)
function burn(address to) external returns (uint amount0, uint amount1)
function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external
```

Functions should not be referenced directly, should be interacted with via the BaseV1Router

Fees are not accrued in the base pair themselves, but are transfered to `BaseV1Fees` which has a 1:1 relationship with `BaseV1Pair`

### BaseV1Factory

Base V1 factory allows for the creation of `pools` via ```function createPair(address tokenA, address tokenB, bool stable) external returns (address pair)```

Anyone can create a pool permissionlessly.

### BaseV1Router

Base V1 router is a wrapper contract and the default entry point into Stable V1 pools.

```
function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
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

Gauges distribute arbitrary `token(s)` rewards to BaseV1Pair LPs based on voting weights as defined by `ve` voters.

Arbitrary rewards can be added permissionlessly via ```function notifyRewardAmount(address token, uint amount) external```

## Bribe

Gauge bribes are natively supported by the protocol, Bribes inherit from Gauges and are automatically adjusted on votes.

Users that voted can claim their bribes via calling ```function getReward(address token) public```

Fees accrued by `Gauges` are distributed to `Bribes`

### GaugeV1Factory

Gauge factory permissionlessly creates gauges for `pools` created by StableV1Factory. Further it handles voting for 60% of the incentives to `pools`.

```
function vote(address[] calldata _poolVote, uint[] calldata _weights) external
function distribute(address token) external
```
