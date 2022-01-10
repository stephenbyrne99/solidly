// SPDX-License-Identifier: MIT

pragma solidity 0.8.11;

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

interface IBaseV1Callee {
    function hook(address sender, uint amount0, uint amount1, bytes calldata data) external;
}

library UQ112x112 {
    uint224 constant Q112 = 2**112;

    // encode a uint112 as a UQ112x112
    function encode(uint112 y) internal pure returns (uint224 z) {
        z = uint224(y) * Q112; // never overflows
    }

    // divide a UQ112x112 by a uint112, returning a UQ112x112
    function uqdiv(uint224 x, uint112 y) internal pure returns (uint224 z) {
        z = x / uint224(y);
    }
}

contract BaseV1Fees {
    address immutable pair;
    address immutable token0;
    address immutable token1;
    constructor(address _token0, address _token1) {
        pair = msg.sender;
        token0 = _token0;
        token1 = _token1;
    }

    function _safeTransfer(address token,address to,uint256 value) internal {
        (bool success, bytes memory data) =
            token.call(abi.encodeWithSelector(erc20.transfer.selector, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))));
    }

    function claimFeesFor(address recipient, uint amount0, uint amount1) external {
        require(msg.sender == pair);
        if (amount0 > 0) _safeTransfer(token0, recipient, amount0);
        if (amount1 > 0) _safeTransfer(token1, recipient, amount1);
    }

}

contract BaseV1Pair {
    using UQ112x112 for uint224;

    string public name;
    string public symbol;
    uint8 public decimals;

    bool public stable;

    uint public totalSupply = 0;

    mapping(address => mapping (address => uint)) public allowance;
    mapping(address => uint) public balanceOf;

    bytes32 public DOMAIN_SEPARATOR;
    // keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
    bytes32 public constant PERMIT_TYPEHASH = 0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;
    mapping(address => uint) public nonces;

    uint public constant MINIMUM_LIQUIDITY = 10**3;

    event Transfer(address indexed from, address indexed to, uint amount);
    event Approval(address indexed owner, address indexed spender, uint amount);

    address public factory;
    address public token0;
    address public token1;
    address public fees;

    uint decimals0;
    uint decimals1;

    uint112 public reserve0;
    uint112 public reserve1;
    uint32 public blockTimestampLast;

    uint public price0CumulativeLast;
    uint public price1CumulativeLast;
    uint public kLast;

    uint public index0 = 0;
    uint public index1 = 0;

    mapping(address => uint) public supplyIndex0;
    mapping(address => uint) public supplyIndex1;

    function _update0(uint amount) internal {
        _safeTransfer(token0, fees, amount);
        uint256 _ratio = amount * 1e18 / totalSupply;
        if (_ratio > 0) {
          index0 += _ratio;
        }
    }

    function _update1(uint amount) internal {
        _safeTransfer(token1, fees, amount);
        uint256 _ratio = amount * 1e18 / totalSupply;
        if (_ratio > 0) {
          index1 += _ratio;
        }
    }

    mapping(address => uint) public claimable0;
    mapping(address => uint) public claimable1;

    function claimFees() external {
        claimFeesFor(msg.sender);
    }

    function claimFeesFor(address recipient) public lock {
        _updateFor(recipient);

        uint _claimable0 = claimable0[recipient];
        uint _claimable1 = claimable1[recipient];

        claimable0[recipient] = 0;
        claimable1[recipient] = 0;

        BaseV1Fees(fees).claimFeesFor(recipient, _claimable0, _claimable1);
    }

    function _updateFor(address recipient) internal {
        uint _supplied = balanceOf[recipient];
        if (_supplied > 0) {
            uint _supplyIndex0 = supplyIndex0[recipient];
            uint _supplyIndex1 = supplyIndex1[recipient];
            uint _index0 = index0;
            uint _index1 = index1;
            supplyIndex0[recipient] = _index0;
            supplyIndex1[recipient] = _index1;
            uint _delta0 = _index0 - _supplyIndex0;
            uint _delta1 = _index1 - _supplyIndex1;
            if (_delta0 > 0) {
              uint _share = _supplied * _delta0 / 1e18;
              claimable0[recipient] += _share;
            }
            if (_delta1 > 0) {
              uint _share = _supplied * _delta1 / 1e18;
              claimable1[recipient] += _share;
            }
        } else {
            supplyIndex0[recipient] = index0;
            supplyIndex1[recipient] = index1;
        }
    }

    function getReserves() public view returns (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) {
        _reserve0 = reserve0;
        _reserve1 = reserve1;
        _blockTimestampLast = blockTimestampLast;
    }

    function getDecimals() public view returns (uint _decimals0, uint _decimals1) {
        _decimals0 = decimals0;
        _decimals1 = decimals1;
    }

    event Mint(address indexed sender, uint amount0, uint amount1);
    event Burn(address indexed sender, uint amount0, uint amount1, address indexed to);
    event Swap(
        address indexed sender,
        uint amount0In,
        uint amount1In,
        uint amount0Out,
        uint amount1Out,
        address indexed to
    );
    event Sync(uint112 reserve0, uint112 reserve1);


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

    constructor() {
        factory = msg.sender;
        uint chainId;
        assembly {
            chainId := chainid()
        }
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256('EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)'),
                keccak256(bytes(name)),
                keccak256(bytes('1')),
                chainId,
                address(this)
            )
        );
    }

    // called once by the factory at time of deployment
    function initialize(address _token0, address _token1, bool _stable) external {
        require(msg.sender == factory, 'StableV1: FORBIDDEN'); // sufficient check
        token0 = _token0;
        token1 = _token1;
        stable = _stable;
        fees = address(new BaseV1Fees(_token0, _token1));
        if (_stable) {
            decimals = 6;
            decimals0 = 10**(erc20(_token0).decimals()-6);
            decimals1 = 10**(erc20(_token1).decimals()-6);
            name = string(abi.encodePacked("StableV1 AMM - ", erc20(_token0).symbol(), "/", erc20(_token1).symbol()));
            symbol = string(abi.encodePacked("sAMM-", erc20(_token0).symbol(), "/", erc20(_token1).symbol()));
        } else {
            decimals = 18;
            decimals0 = 1;
            decimals1 = 1;
            name = string(abi.encodePacked("VolatileV1 AMM - ", erc20(_token0).symbol(), "/", erc20(_token1).symbol()));
            symbol = string(abi.encodePacked("vAMM-", erc20(_token0).symbol(), "/", erc20(_token1).symbol()));
        }
    }

    // update reserves and, on the first call per block, price accumulators
    function _update(uint balance0, uint balance1, uint112 _reserve0, uint112 _reserve1) private {
        require(balance0 <= type(uint112).max && balance1 <= type(uint112).max, 'BaseV1: OVERFLOW');
        uint32 blockTimestamp = uint32(block.timestamp % 2**32);
        uint32 timeElapsed = blockTimestamp - blockTimestampLast; // overflow is desired
        if (timeElapsed > 0 && _reserve0 != 0 && _reserve1 != 0) {
            price0CumulativeLast += uint(UQ112x112.encode(_reserve1).uqdiv(_reserve0)) * timeElapsed;
            price1CumulativeLast += uint(UQ112x112.encode(_reserve0).uqdiv(_reserve1)) * timeElapsed;
        }
        reserve0 = uint112(balance0);
        reserve1 = uint112(balance1);
        blockTimestampLast = blockTimestamp;
        emit Sync(uint112(reserve0), uint112(reserve1));
    }

    uint _unlocked = 1;
    modifier lock() {
        require(_unlocked == 1);
        _unlocked = 0;
        _;
        _unlocked = 1;
    }

    // this low-level function should be called from a contract which performs important safety checks
    function mint(address to) external lock returns (uint liquidity) {
        (uint112 _reserve0, uint112 _reserve1,) = getReserves(); // gas savings
        uint _balance0 = erc20(token0).balanceOf(address(this));
        uint _balance1 = erc20(token1).balanceOf(address(this));
        uint _amount0 = _balance0 - _reserve0;
        uint _amount1 = _balance1 - _reserve1;

        uint _totalSupply = totalSupply; // gas savings, must be defined here since totalSupply can update in _mintFee
        if (_totalSupply == 0) {
            liquidity = Math.sqrt(_amount0 * _amount1) - MINIMUM_LIQUIDITY;
            _mint(address(0), MINIMUM_LIQUIDITY); // permanently lock the first MINIMUM_LIQUIDITY tokens
        } else {
            liquidity = Math.min(_amount0 * _totalSupply / _reserve0, _amount1 * _totalSupply / _reserve1);
        }
        require(liquidity > 0, 'ILM'); // BaseV1: INSUFFICIENT_LIQUIDITY_MINTED
        _mint(to, liquidity);

        _update(_balance0, _balance1, _reserve0, _reserve1);
        emit Mint(msg.sender, _amount0, _amount1);
    }

    // this low-level function should be called from a contract which performs important safety checks
    function burn(address to) external lock returns (uint amount0, uint amount1) {
        (uint112 _reserve0, uint112 _reserve1,) = getReserves(); // gas savings
        address _token0 = token0;                                // gas savings
        address _token1 = token1;                                // gas savings
        uint balance0 = erc20(_token0).balanceOf(address(this));
        uint balance1 = erc20(_token1).balanceOf(address(this));
        uint liquidity = balanceOf[address(this)];

        uint _totalSupply = totalSupply; // gas savings, must be defined here since totalSupply can update in _mintFee
        amount0 = liquidity * balance0 / _totalSupply; // using balances ensures pro-rata distribution
        amount1 = liquidity * balance1 / _totalSupply; // using balances ensures pro-rata distribution
        require(amount0 > 0 && amount1 > 0, 'ILB'); // BaseV1: INSUFFICIENT_LIQUIDITY_BURNED
        _burn(address(this), liquidity);
        _safeTransfer(_token0, to, amount0);
        _safeTransfer(_token1, to, amount1);
        balance0 = erc20(_token0).balanceOf(address(this));
        balance1 = erc20(_token1).balanceOf(address(this));

        _update(balance0, balance1, _reserve0, _reserve1);
        emit Burn(msg.sender, amount0, amount1, to);
    }

    // this low-level function should be called from a contract which performs important safety checks
    function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external lock {
        require(amount0Out > 0 || amount1Out > 0, 'IOA'); // BaseV1: INSUFFICIENT_OUTPUT_AMOUNT
        (uint112 _reserve0, uint112 _reserve1,) = getReserves(); // gas savings
        require(amount0Out < _reserve0 && amount1Out < _reserve1, 'BaseV1: INSUFFICIENT_LIQUIDITY');

        uint _balance0;
        uint _balance1;
        { // scope for _token{0,1}, avoids stack too deep errors
        address _token0 = token0;
        address _token1 = token1;
        require(to != _token0 && to != _token1, 'IT'); // BaseV1: INVALID_TO
        if (amount0Out > 0) _safeTransfer(_token0, to, amount0Out); // optimistically transfer tokens
        if (amount1Out > 0) _safeTransfer(_token1, to, amount1Out); // optimistically transfer tokens
        if (data.length > 0) IBaseV1Callee(to).hook(msg.sender, amount0Out, amount1Out, data);
        _balance0 = erc20(_token0).balanceOf(address(this));
        _balance1 = erc20(_token1).balanceOf(address(this));
        }
        uint amount0In = _balance0 > _reserve0 - amount0Out ? _balance0 - (_reserve0 - amount0Out) : 0;
        uint amount1In = _balance1 > _reserve1 - amount1Out ? _balance1 - (_reserve1 - amount1Out) : 0;
        require(amount0In > 0 || amount1In > 0, 'IOA'); // BaseV1: INSUFFICIENT_INPUT_AMOUNT
        { // scope for reserve{0,1}Adjusted, avoids stack too deep errors
        address _token0 = token0;
        address _token1 = token1;
        if (amount0In > 0) _update0(amount0In / 10000); // accrue fees for token0
        if (amount1In > 0) _update1(amount1In / 10000); // accrue fees for token1
        _balance0 = erc20(_token0).balanceOf(address(this));
        _balance1 = erc20(_token1).balanceOf(address(this));
        require(_k(_balance0/decimals0, _balance1/decimals1) > _k(_reserve0/decimals0, _reserve1/decimals1), 'K'); // BaseV1: K
        }

        _update(_balance0, _balance1, _reserve0, _reserve1);
        emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
    }

    // force balances to match reserves
    function skim(address to) external lock {
        address _token0 = token0; // gas savings
        address _token1 = token1; // gas savings
        _safeTransfer(_token0, to, erc20(_token0).balanceOf(address(this)) - (reserve0));
        _safeTransfer(_token1, to, erc20(_token1).balanceOf(address(this)) - (reserve1));
    }

    // force reserves to match balances
    function sync() external lock {
        _update(erc20(token0).balanceOf(address(this)), erc20(token1).balanceOf(address(this)), reserve0, reserve1);
    }

    function quote(uint amountA, uint reserveA, uint reserveB) external view returns (uint) {
        if (stable) {
            return Math.sqrt(Math.sqrt(_k(amountA+reserveA, reserveB))) * 2;
        } else {
            return amountA * reserveB / reserveA;
        }
    }

    function getAmountOut(uint amountIn, address tokenIn) external view returns (uint) {
        (uint reserveA, uint reserveB,) = getReserves();
        (reserveA, reserveB) = tokenIn == token0 ? (reserveA, reserveB) : (reserveB, reserveA);
        if (stable) {
            return Math.sqrt(Math.sqrt(_k(amountIn+reserveA, reserveB))) * 2;
        } else {
            return amountIn * reserveB / reserveA;
        }
    }

    function _k(uint x, uint y) internal view returns (uint) {
      if (stable) {
          return x * y * (x**2+y**2) / 2;
      } else {
          return x * y;
      }
    }

    function _mint(address dst, uint amount) internal {
        _updateFor(dst);
        totalSupply += amount;
        balanceOf[dst] += amount;
        emit Transfer(address(0), dst, amount);
    }

    function _burn(address dst, uint amount) internal {
        _updateFor(dst);
        totalSupply -= amount;
        balanceOf[dst] -= amount;
        emit Transfer(dst, address(0), amount);
    }

    function approve(address spender, uint amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;

        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function permit(address owner, address spender, uint value, uint deadline, uint8 v, bytes32 r, bytes32 s) external {
        require(deadline >= block.timestamp, 'BaseV1: EXPIRED');
        bytes32 digest = keccak256(
            abi.encodePacked(
                '\x19\x01',
                DOMAIN_SEPARATOR,
                keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, nonces[owner]++, deadline))
            )
        );
        address recoveredAddress = ecrecover(digest, v, r, s);
        require(recoveredAddress != address(0) && recoveredAddress == owner, 'BaseV1: INVALID_SIGNATURE');
        allowance[owner][spender] = value;

        emit Approval(owner, spender, value);
    }

    function transfer(address dst, uint amount) external returns (bool) {
        _transferTokens(msg.sender, dst, amount);
        return true;
    }

    function transferFrom(address src, address dst, uint amount) external returns (bool) {
        address spender = msg.sender;
        uint spenderAllowance = allowance[src][spender];

        if (spender != src && spenderAllowance != type(uint).max) {
            uint newAllowance = spenderAllowance - amount;
            allowance[src][spender] = newAllowance;

            emit Approval(src, spender, newAllowance);
        }

        _transferTokens(src, dst, amount);
        return true;
    }

    function _transferTokens(address src, address dst, uint amount) internal {
        _updateFor(src);
        _updateFor(dst);

        balanceOf[src] -= amount;
        balanceOf[dst] += amount;

        emit Transfer(src, dst, amount);
    }
}

contract BaseV1Factory {

    mapping(address => mapping(address => mapping(bool => address))) public getPair;
    address[] public allPairs;
    mapping(address => bool) public isPair;

    event PairCreated(address indexed token0, address indexed token1, bool stable, address pair, uint);

    function allPairsLength() external view returns (uint) {
        return allPairs.length;
    }

    function pairCodeHash() external pure returns (bytes32) {
        return keccak256(type(BaseV1Pair).creationCode);
    }

    function createPair(address tokenA, address tokenB, bool stable) external returns (address pair) {
        require(tokenA != tokenB, 'IA'); // BaseV1: IDENTICAL_ADDRESSES
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), 'ZA'); // BaseV1: ZERO_ADDRESS
        require(getPair[token0][token1][stable] == address(0), 'PE'); // BaseV1: PAIR_EXISTS - single check is sufficient
        bytes memory bytecode = type(BaseV1Pair).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(token0, token1, stable));
        assembly {
            pair := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        BaseV1Pair(pair).initialize(token0, token1, stable);
        getPair[token0][token1][stable] = pair;
        getPair[token1][token0][stable] = pair; // populate mapping in the reverse direction
        allPairs.push(pair);
        isPair[pair] = true;
        emit PairCreated(token0, token1, stable, pair, allPairs.length);
    }
}
