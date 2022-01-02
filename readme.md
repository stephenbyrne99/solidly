# stableswap

## ve

Vested Escrow (ve), this is the core voting mechanism of the system, used by `StableV1Factory` for gauge rewards and gauge voting

* Added native delegation
* `deposit_for` deposits on behalf of

## StableV1Pair

Stable V1 pair is the base pair, it holds 2 closely correlated assets (example MIM-UST), it uses the standard UniswapV2Pair interface for UI & analytics compatability.

Functions should not be referenced directly, should be interacted with via the StableV1Router

## Gauge

Gauges distribute `token` rewards to StableV1Pair LPs based on voting weights as defined by `ve` voters.

## 