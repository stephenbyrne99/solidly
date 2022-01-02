// SPDX-License-Identifier: MIT

pragma solidity ^0.8.6;

interface ve {
    function locked__end(address) external view returns (uint);
    function deposit_for(address, uint) external;
    function token() external view returns (address);
    function get_adjusted_ve_balance(address, address) external view returns (uint);
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

interface IStableV1Callee {
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

contract StableV1Pair {
    using UQ112x112 for uint224;
    
    string public name;
    string public symbol;
    uint8 public constant decimals = 6;
    
    uint public totalSupply = 0;
    
    mapping(address => mapping (address => uint)) public allowance;
    mapping(address => uint) public balanceOf;

    bytes32 public DOMAIN_SEPARATOR;
    // keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
    bytes32 public constant PERMIT_TYPEHASH = 0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;
    mapping(address => uint) public nonces;
    
    event Transfer(address indexed from, address indexed to, uint amount);
    event Approval(address indexed owner, address indexed spender, uint amount);
    
    address public factory;
    address public token0;
    address public token1;
    
    uint decimals0;
    uint decimals1;

    uint112 public reserve0;
    uint112 public reserve1;
    uint32 public blockTimestampLast;

    uint public price0CumulativeLast;
    uint public price1CumulativeLast;
    uint public kLast;

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
    function initialize(address _token0, address _token1) external {
        require(msg.sender == factory, 'StableV1: FORBIDDEN'); // sufficient check
        token0 = _token0;
        token1 = _token1;
        decimals0 = 10**(erc20(_token0).decimals()-6);
        decimals1 = 10**(erc20(_token1).decimals()-6);
        name = string(abi.encodePacked("Stable AMM - ", erc20(_token0).symbol(), "/", erc20(_token1).symbol()));
        symbol = string(abi.encodePacked("sAMM-", erc20(_token0).symbol(), "/", erc20(_token1).symbol()));
    }

    // update reserves and, on the first call per block, price accumulators
    function _update(uint balance0, uint balance1, uint112 _reserve0, uint112 _reserve1) private {
        require(balance0 <= type(uint112).max && balance1 <= type(uint112).max, 'StableV1: OVERFLOW');
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

        if (totalSupply == 0) {
            liquidity = _lp(_amount0/decimals0, _amount1/decimals1);
        } else {
            liquidity = _lp(_balance0/decimals0, _balance1/decimals1) - _lp(_reserve0/decimals0, _reserve1/decimals1);
        }

        require(liquidity > 0, 'StableV1: INSUFFICIENT_LIQUIDITY_MINTED');
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
        require(amount0 > 0 && amount1 > 0, 'StableV1: INSUFFICIENT_LIQUIDITY_BURNED');
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
        require(amount0Out > 0 || amount1Out > 0, 'StableV1: INSUFFICIENT_OUTPUT_AMOUNT');
        (uint112 _reserve0, uint112 _reserve1,) = getReserves(); // gas savings
        require(amount0Out < _reserve0 && amount1Out < _reserve1, 'StableV1: INSUFFICIENT_LIQUIDITY');

        uint _balance0;
        uint _balance1;
        { // scope for _token{0,1}, avoids stack too deep errors
        address _token0 = token0;
        address _token1 = token1;
        require(to != _token0 && to != _token1, 'StableV1: INVALID_TO');
        if (amount0Out > 0) _safeTransfer(_token0, to, amount0Out); // optimistically transfer tokens
        if (amount1Out > 0) _safeTransfer(_token1, to, amount1Out); // optimistically transfer tokens
        if (data.length > 0) IStableV1Callee(to).hook(msg.sender, amount0Out, amount1Out, data);
        _balance0 = erc20(_token0).balanceOf(address(this));
        _balance1 = erc20(_token1).balanceOf(address(this));
        }
        uint amount0In = _balance0 > _reserve0 - amount0Out ? _balance0 - (_reserve0 - amount0Out) : 0;
        uint amount1In = _balance1 > _reserve1 - amount1Out ? _balance1 - (_reserve1 - amount1Out) : 0;
        require(amount0In > 0 || amount1In > 0, 'StableV1: INSUFFICIENT_INPUT_AMOUNT');
        { // scope for reserve{0,1}Adjusted, avoids stack too deep errors
        address _token0 = token0;
        address _token1 = token1;
        address feeTo = StableV1Factory(factory).feeTo();
        if (amount0In > 0) _safeTransfer(_token0, feeTo, amount0In / 100000);
        if (amount1In > 0) _safeTransfer(_token1, feeTo, amount1In / 100000);
        _balance0 = erc20(_token0).balanceOf(address(this));
        _balance1 = erc20(_token1).balanceOf(address(this));
        require(_curve(_balance0/decimals0, _balance1/decimals1) > _curve(_reserve0/decimals0, _reserve1/decimals1), 'StableV1: K');
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
    
    function _lp(uint x, uint y) internal pure returns (uint) {
        return Math.sqrt(Math.sqrt(_curve(x, y))) * 2;
    }
    
    function _curve(uint x, uint y) internal pure returns (uint) {
        return x * y * (x**2+y**2) / 2;
    }
    
    function _mint(address dst, uint amount) internal {
        totalSupply += amount;
        balanceOf[dst] += amount;
        emit Transfer(address(0), dst, amount);
    }
        
    function _burn(address dst, uint amount) internal {
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
        require(deadline >= block.timestamp, 'StableV1: EXPIRED');
        bytes32 digest = keccak256(
            abi.encodePacked(
                '\x19\x01',
                DOMAIN_SEPARATOR,
                keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, nonces[owner]++, deadline))
            )
        );
        address recoveredAddress = ecrecover(digest, v, r, s);
        require(recoveredAddress != address(0) && recoveredAddress == owner, 'StableV1: INVALID_SIGNATURE');
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
        balanceOf[src] -= amount;
        balanceOf[dst] += amount;
        
        emit Transfer(src, dst, amount);
    }
}



contract Gauge {
    
    uint constant DURATION = 7 days;
    uint constant PRECISION = 10 ** 18;
    uint constant MAXTIME = 4 * 365 * 86400;
    
    address public immutable stake;
    address immutable _ve;
    address immutable _token;
    
    mapping(address => uint) public rewardRate;
    mapping(address => uint) public periodFinish;
    mapping(address => uint) public lastUpdateTime;
    mapping(address => uint) public rewardPerTokenStored;
    
    mapping(address => mapping(address => uint)) public userRewardPerTokenPaid;
    mapping(address => mapping(address => uint)) public rewards;

    uint public totalSupply;
    uint public derivedSupply;
    mapping(address => uint) public balanceOf;
    mapping(address => uint) public derivedBalances;
    
    constructor(address _stake) {
        stake = _stake;
        address __ve = StableV1Factory(msg.sender)._ve();
        _ve = __ve;
        _token = ve(__ve).token();
    }

    function lastTimeRewardApplicable(address token) public view returns (uint) {
        return Math.min(block.timestamp, periodFinish[token]);
    }

    function rewardPerToken(address token) public view returns (uint) {
        if (totalSupply == 0) {
            return rewardPerTokenStored[token];
        }
        return rewardPerTokenStored[token] + ((lastTimeRewardApplicable(token) - lastUpdateTime[token]) * rewardRate[token] * PRECISION / derivedSupply);
    }
    
    function derivedBalance(address account) public view returns (uint) {
        uint _balance = balanceOf[account];
        uint _derived = _balance * 40 / 100;
        uint _adjusted = (totalSupply * ve(_ve).get_adjusted_ve_balance(account, address(this)) / erc20(_ve).totalSupply()) * 60 / 100;
        return Math.min(_derived + _adjusted, _balance);
    }
    
    function kick(address account) public {
        uint _derivedBalance = derivedBalances[account];
        derivedSupply -= _derivedBalance;
        _derivedBalance = derivedBalance(account);
        derivedBalances[account] = _derivedBalance;
        derivedSupply += _derivedBalance;
    }

    function earned(address token, address account) public view returns (uint) {
        return (derivedBalances[account] * (rewardPerToken(token) - userRewardPerTokenPaid[token][account]) / PRECISION) + rewards[token][account];
    }

    function getRewardForDuration(address token) external view returns (uint) {
        return rewardRate[token] * DURATION;
    }
    
    function deposit() external {
        _deposit(erc20(stake).balanceOf(msg.sender), msg.sender);
    }
    
    function deposit(uint amount) external {
        _deposit(amount, msg.sender);
    }
    
    function deposit(uint amount, address account) external {
        _deposit(amount, account);
    }
    
    function _deposit(uint amount, address account) internal updateReward(_token, account) {
        totalSupply += amount;
        balanceOf[account] += amount;
        _safeTransferFrom(stake, account, address(this), amount);
    }
    
    function withdraw() external {
        _withdraw(balanceOf[msg.sender]);
    }

    function withdraw(uint amount) external {
        _withdraw(amount);
    }
    
    function _withdraw(uint amount) internal updateReward(_token, msg.sender) {
        totalSupply -= amount;
        balanceOf[msg.sender] -= amount;
        _safeTransfer(stake, msg.sender, amount);
    }

    function getReward(address token) public updateReward(token, msg.sender) {
        uint _reward = rewards[token][msg.sender];
        rewards[token][msg.sender] = 0;
        _safeTransfer(token, msg.sender, _reward);
    }

    function exit() external {
       _withdraw(balanceOf[msg.sender]);
        getReward(_token);
    }
    
    function notifyRewardAmount(address token, uint amount) external updateReward(token, address(0)) {
        if (block.timestamp >= periodFinish[token]) {
            rewardRate[token] = amount / DURATION;
        } else {
            uint _remaining = periodFinish[token] - block.timestamp;
            uint _left = _remaining * rewardRate[token];
            rewardRate[token] = (amount + _left) / DURATION;
        }
        
        lastUpdateTime[token] = block.timestamp;
        periodFinish[token] = block.timestamp + DURATION;
    }

    modifier updateReward(address token, address account) {
        rewardPerTokenStored[token] = rewardPerToken(token);
        lastUpdateTime[token] = lastTimeRewardApplicable(token);
        if (account != address(0)) {
            rewards[token][account] = earned(token, account);
            userRewardPerTokenPaid[token][account] = rewardPerTokenStored[token];
        }
        _;
        if (account != address(0)) {
            kick(account);
        }
    }
    
    function _safeTransfer(address token, address to, uint256 value) internal {
        (bool success, bytes memory data) =
            token.call(abi.encodeWithSelector(erc20.transfer.selector, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))));
    }
    
    function _safeTransferFrom(address token, address from, address to, uint256 value) internal {
        (bool success, bytes memory data) =
            token.call(abi.encodeWithSelector(erc20.transferFrom.selector, from, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))));
    }
}

contract StableV1Factory {

    address public feeTo;

    mapping(address => mapping(address => address)) public getPair;
    address[] public allPairs;

    event PairCreated(address indexed token0, address indexed token1, address pair, uint);

    function allPairsLength() external view returns (uint) {
        return allPairs.length;
    }

    function pairCodeHash() external pure returns (bytes32) {
        return keccak256(type(StableV1Pair).creationCode);
    }

    function createPair(address tokenA, address tokenB) external returns (address pair) {
        require(tokenA != tokenB, 'StableV1: IDENTICAL_ADDRESSES');
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), 'StableV1: ZERO_ADDRESS');
        require(getPair[token0][token1] == address(0), 'StableV1: PAIR_EXISTS'); // single check is sufficient
        bytes memory bytecode = type(StableV1Pair).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        assembly {
            pair := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        StableV1Pair(pair).initialize(token0, token1);
        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair; // populate mapping in the reverse direction
        allPairs.push(pair);
        _addGauge(pair);
        emit PairCreated(token0, token1, pair, allPairs.length);
    }

    function setFeeTo(address _feeTo) external onlyG {
        feeTo = _feeTo;
    }

    address public immutable _ve;
    address public immutable base;
    address constant ZERO_ADDRESS = 0x0000000000000000000000000000000000000000;
    
    uint public totalWeight;
    
    address public gov;
    address public nextgov;
    uint public commitgov;
    uint public constant delay = 1 days;
    
    address[] internal _tokens;
    mapping(address => address) public gauges; // token => gauge
    mapping(address => uint) public weights; // token => weight
    mapping(address => mapping(address => uint)) public votes; // msg.sender => votes
    mapping(address => address[]) public tokenVote;// msg.sender => token
    mapping(address => uint) public usedWeights;  // msg.sender => total voting weight of user
    mapping(address => bool) public enabled;
    
    function tokens() external view returns (address[] memory) {
        return _tokens;
    }
    
    constructor(address __ve) {
        gov = msg.sender;
        _ve = __ve;
        base = ve(__ve).token();
    }
    
    modifier onlyG() {
        require(msg.sender == gov);
        _;
    }
    
    function setGov(address _gov) external onlyG {
        nextgov = _gov;
        commitgov = block.timestamp + delay;
    }
    
    function acceptGov() external {
        require(msg.sender == nextgov && commitgov < block.timestamp);
        gov = nextgov;
    }
    
    function reset() external {
        _reset(msg.sender);
    }
    
    function _reset(address _owner) internal {
        address[] storage _tokenVote = tokenVote[_owner];
        uint _tokenVoteCnt = _tokenVote.length;

        for (uint i = 0; i < _tokenVoteCnt; i ++) {
            address _token = _tokenVote[i];
            uint _votes = votes[_owner][_token];
            
            if (_votes > 0) {
                totalWeight -= _votes;
                weights[_token] -= _votes;
                votes[_owner][_token] = 0;
            }
        }

        delete tokenVote[_owner];
    }
    
    function poke(address _owner) public {
        address[] memory _tokenVote = tokenVote[_owner];
        uint _tokenCnt = _tokenVote.length;
        uint[] memory _weights = new uint[](_tokenCnt);
        
        uint _prevUsedWeight = usedWeights[_owner];
        uint _weight = ve(_ve).get_adjusted_ve_balance(_owner, ZERO_ADDRESS);

        for (uint i = 0; i < _tokenCnt; i ++) {
            uint _prevWeight = votes[_owner][_tokenVote[i]];
            _weights[i] = _prevWeight * _weight / _prevUsedWeight;
        }

        _vote(_owner, _tokenVote, _weights);
    }
    
    function _vote(address _owner, address[] memory _tokenVote, uint[] memory _weights) internal {
        // _weights[i] = percentage * 100
        _reset(_owner);
        uint _tokenCnt = _tokenVote.length;
        uint _weight = ve(_ve).get_adjusted_ve_balance(_owner, ZERO_ADDRESS);
        uint _totalVoteWeight = 0;
        uint _usedWeight = 0;

        for (uint i = 0; i < _tokenCnt; i ++) {
            _totalVoteWeight += _weights[i];
        }

        for (uint i = 0; i < _tokenCnt; i ++) {
            address _token = _tokenVote[i];
            address _gauge = gauges[_token];
            uint _tokenWeight = _weights[i] * _weight / _totalVoteWeight;

            if (_gauge != address(0x0)) {
                _usedWeight += _tokenWeight;
                totalWeight += _tokenWeight;
                weights[_token] += _tokenWeight;
                tokenVote[_owner].push(_token);
                votes[_owner][_token] = _tokenWeight;
            }
        }

        usedWeights[_owner] = _usedWeight;
    }
    
    function vote(address[] calldata _tokenVote, uint[] calldata _weights) external {
        require(_tokenVote.length == _weights.length);
        _vote(msg.sender, _tokenVote, _weights);
    }
    
    function _addGauge(address _token) internal {
        require(gauges[_token] == address(0x0), "exists");
        address _gauge = address(new Gauge(_token));
        gauges[_token] = _gauge;
        enabled[_token] = true;
        _tokens.push(_token);
    }
    
    function disable(address _token) external onlyG {
        enabled[_token] = false;
    }
    
    function enable(address _token) external onlyG {
        enabled[_token] = true;
    }
    
    function length() external view returns (uint) {
        return _tokens.length;
    }
    
    function distribute() external {
        uint _balance = erc20(base).balanceOf(address(this));
        if (_balance > 0 && totalWeight > 0) {
            uint _totalWeight = totalWeight;
            for (uint i = 0; i < _tokens.length; i++) {
                if (!enabled[_tokens[i]]) {
                    _totalWeight -= weights[_tokens[i]];
                }
            }
            for (uint x = 0; x < _tokens.length; x++) {
                if (enabled[_tokens[x]]) {
                    uint _reward = _balance * weights[_tokens[x]] / _totalWeight;
                    if (_reward > 0) {
                        address _gauge = gauges[_tokens[x]];
                        _safeTransfer(base, _gauge, _reward);
                        Gauge(_gauge).notifyRewardAmount(base, _reward);
                    }
                }
            }
        }
    }
    
    function _safeTransfer(address token, address to, uint256 value) internal {
        (bool success, bytes memory data) =
            token.call(abi.encodeWithSelector(erc20.transfer.selector, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))));
    }
}
