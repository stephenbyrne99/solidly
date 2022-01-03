// SPDX-License-Identifier: MIT

pragma solidity ^0.8.6;

interface IStableV1Factory {
    function allPairsLength() external view returns (uint);
    function pairCodeHash() external pure returns (bytes32);
    function getPair(address, address) external view returns (address);
    function createPair(address tokenA, address tokenB) external returns (address pair);
}

interface IStableV1Pair {
    function transferFrom(address src, address dst, uint amount) external returns (bool);
    function permit(address owner, address spender, uint value, uint deadline, uint8 v, bytes32 r, bytes32 s) external;
    function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external;
    function burn(address to) external returns (uint amount0, uint amount1);
    function mint(address to) external returns (uint liquidity);
    function getReserves() external view returns (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast);
    function getDecimals() external view returns (uint _decimals0, uint _decimals1);
}

interface erc20 {
    function totalSupply() external view returns (uint256);
    function transfer(address recipient, uint amount) external returns (bool);
    function decimals() external view returns (uint8);
    function symbol() external view returns (string memory);
    function balanceOf(address) external view returns (uint);
    function transferFrom(address sender, address recipient, uint amount) external returns (bool);
    function approve(address spender, uint value) external returns (bool);
}

library Math {
    function max(uint a, uint b) internal pure returns (uint) {
        return a >= b ? a : b;
    }
    function min(uint a, uint b) internal pure returns (uint) {
        return a < b ? a : b;
    }
    function sqrt(uint y) internal pure returns (uint z) {
        if (y > 3) {
            z = y;
            uint x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }
}

library StableV1Library {

    // returns sorted token addresses, used to handle return values from pairs sorted in this order
    function sortTokens(address tokenA, address tokenB) internal pure returns (address token0, address token1) {
        require(tokenA != tokenB, 'StableV1Library: IDENTICAL_ADDRESSES');
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), 'StableV1Library: ZERO_ADDRESS');
    }

    // calculates the CREATE2 address for a pair without making any external calls
    function pairFor(address factory, address tokenA, address tokenB) internal pure returns (address pair) {
        (address token0, address token1) = sortTokens(tokenA, tokenB);
        pair = address(uint160(uint256(keccak256(abi.encodePacked(
                hex'ff',
                factory,
                keccak256(abi.encodePacked(token0, token1)),
                hex'23b1a9e50f16bab3f9e1ffc37e8b633d0daf5c5bbb4eddaddb52c60c2e782db1' // init code hash
            )))));
    }

    // fetches and sorts the reserves for a pair
    function getReserves(address factory, address tokenA, address tokenB) internal view returns (uint reserveA, uint reserveB) {
        (address token0,) = sortTokens(tokenA, tokenB);
        (uint reserve0, uint reserve1,) = IStableV1Pair(pairFor(factory, tokenA, tokenB)).getReserves();
        (reserveA, reserveB) = tokenA == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
    }

    // fetches and sorts the reserves for a pair
    function getDecimals(address factory, address tokenA, address tokenB) internal view returns (uint decimalA, uint decimalB) {
        (address token0,) = sortTokens(tokenA, tokenB);
        (uint decimal0, uint decimal1) = IStableV1Pair(pairFor(factory, tokenA, tokenB)).getDecimals();
        (decimalA, decimalB) = tokenA == token0 ? (decimal0, decimal1) : (decimal1, decimal0);
    }

    // given some amount of an asset and pair reserves, returns an equivalent amount of the other asset
    function quote(uint amountA, uint reserveA, uint reserveB, uint decimalsB) internal pure returns (uint amountB) {
        require(amountA > 0, 'StableV1Library: INSUFFICIENT_AMOUNT');
        require(reserveA > 0 && reserveB > 0, 'StableV1Library: INSUFFICIENT_LIQUIDITY');
        amountA -= amountA/100000; // Fee adjustment

        amountB = (_lp(reserveA+amountA, reserveB) - _lp(reserveA, reserveB)) * decimalsB;
    }

    // given some amount of an asset and pair reserves, returns an equivalent amount of the other asset
    function quoteAddLiquidity(address factory, address tokenA, address tokenB, uint amountA, uint amountB) internal view returns (uint liquidity) {
        (uint amount0, uint amount1) = tokenA < tokenB ? (amountA, amountB) : (amountB, amountA);
        (uint reserve0, uint reserve1,) = IStableV1Pair(pairFor(factory, tokenA, tokenB)).getReserves();
        (uint decimals0, uint decimals1) = IStableV1Pair(pairFor(factory, tokenA, tokenB)).getDecimals();

        liquidity = _lp((reserve0+amount0)/decimals0, (reserve1+amount1)/decimals1) - _lp(reserve0/decimals0, reserve1/decimals1);
    }

    // given an input amount of an asset and pair reserves, returns the maximum output amount of the other asset
    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut, uint decimalsOut) internal pure returns (uint amountOut) {
        amountOut = quote(amountIn, reserveIn, reserveOut, decimalsOut);
    }

    // performs chained getAmountOut calculations on any number of pairs
    function getAmountsOut(address factory, uint amountIn, address[] memory path) internal view returns (uint[] memory amounts) {
        require(path.length >= 2, 'UniswapV2Library: INVALID_PATH');
        amounts = new uint[](path.length);
        amounts[0] = amountIn;
        for (uint i; i < path.length - 1; i++) {
            (uint reserveIn, uint reserveOut) = getReserves(factory, path[i], path[i + 1]);
            (uint decimalIn, uint decimalOut) = getDecimals(factory, path[i], path[i + 1]);
            amounts[i + 1] = getAmountOut(amounts[i]/decimalIn, reserveIn/decimalIn, reserveOut/decimalOut, decimalOut);
        }
    }

    function _lp(uint x, uint y) internal pure returns (uint) {
        return Math.sqrt(Math.sqrt(_curve(x, y))) * 2;
    }

    function _curve(uint x, uint y) internal pure returns (uint) {
        return x * y * (x**2+y**2) / 2;
    }
}

contract StableV1Router01 {

    address public immutable factory;

    modifier ensure(uint deadline) {
        require(deadline >= block.timestamp, 'StableV1Router: EXPIRED');
        _;
    }

    constructor(address _factory) {
        factory = _factory;
    }

    function _safeTransfer(address token,address to,uint256 value) internal {
        (bool success, bytes memory data) =
            token.call(abi.encodeWithSelector(erc20.transfer.selector, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))));
    }

    function _safeTransferFrom(address token, address from, address to, uint256 value) internal {
        (bool success, bytes memory data) =
            token.call(abi.encodeWithSelector(erc20.transferFrom.selector, from, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))));
    }

    function sortTokens(address tokenA, address tokenB) external pure returns (address token0, address token1) {
      return StableV1Library.sortTokens(tokenA, tokenB);
    }

    function pairFor(address tokenA, address tokenB) external view returns (address) {
      return StableV1Library.pairFor(factory, tokenA, tokenB);
    }

    function quoteAddLiquidity(address tokenA, address tokenB, uint amountA, uint amountB) external view returns (uint liquidity) {
      return StableV1Library.quoteAddLiquidity(factory, tokenA, tokenB, amountA, amountB);
    }

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint minLiquidity,
        address to,
        uint deadline
    ) external ensure(deadline) returns (uint amountA, uint amountB, uint liquidity) {
        if (IStableV1Factory(factory).getPair(tokenA, tokenB) == address(0)) {
            IStableV1Factory(factory).createPair(tokenA, tokenB);
        }
        (amountA, amountB) = (amountADesired, amountBDesired);
        address pair = StableV1Library.pairFor(factory, tokenA, tokenB);
        _safeTransferFrom(tokenA, msg.sender, pair, amountA);
        _safeTransferFrom(tokenB, msg.sender, pair, amountB);
        liquidity = IStableV1Pair(pair).mint(to);

        require(liquidity >= minLiquidity, '< _min_liquidity');
    }

    // **** REMOVE LIQUIDITY ****
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) public ensure(deadline) returns (uint amountA, uint amountB) {
        address pair = StableV1Library.pairFor(factory, tokenA, tokenB);
        IStableV1Pair(pair).transferFrom(msg.sender, pair, liquidity); // send liquidity to pair
        (uint amount0, uint amount1) = IStableV1Pair(pair).burn(to);
        (address token0,) = StableV1Library.sortTokens(tokenA, tokenB);
        (amountA, amountB) = tokenA == token0 ? (amount0, amount1) : (amount1, amount0);
        require(amountA >= amountAMin, 'StableV1Router: INSUFFICIENT_A_AMOUNT');
        require(amountB >= amountBMin, 'StableV1Router: INSUFFICIENT_B_AMOUNT');
    }

    function removeLiquidityWithPermit(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external returns (uint amountA, uint amountB) {
        address pair = StableV1Library.pairFor(factory, tokenA, tokenB);
        uint value = approveMax ? type(uint).max : liquidity;
        IStableV1Pair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        (amountA, amountB) = removeLiquidity(tokenA, tokenB, liquidity, amountAMin, amountBMin, to, deadline);
    }

    // **** SWAP ****
    // requires the initial amount to have already been sent to the first pair
    function _swap(uint[] memory amounts, address[] memory path, address _to) internal virtual {
        for (uint i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0,) = StableV1Library.sortTokens(input, output);
            uint amountOut = amounts[i + 1];
            (uint amount0Out, uint amount1Out) = input == token0 ? (uint(0), amountOut) : (amountOut, uint(0));
            address to = i < path.length - 2 ? StableV1Library.pairFor(factory, output, path[i + 2]) : _to;
            IStableV1Pair(StableV1Library.pairFor(factory, input, output)).swap(
                amount0Out, amount1Out, to, new bytes(0)
            );
        }
    }
    function getAmountsOut(uint amountIn, address[] memory path) public view returns (uint[] memory amounts) {
        return StableV1Library.getAmountsOut(factory, amountIn, path);
    }
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external ensure(deadline) returns (uint[] memory amounts) {
        amounts = StableV1Library.getAmountsOut(factory, amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, 'UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT');
        _safeTransferFrom(
            path[0], msg.sender, StableV1Library.pairFor(factory, path[0], path[1]), amounts[0]
        );
        _swap(amounts, path, to);
    }
}
