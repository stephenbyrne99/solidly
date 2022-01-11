// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

library Math {
    function max(uint a, uint b) internal pure returns (uint) {
        return a >= b ? a : b;
    }
    function min(uint a, uint b) internal pure returns (uint) {
        return a < b ? a : b;
    }
}

interface erc20 {
    function totalSupply() external view returns (uint256);
    function transfer(address recipient, uint amount) external returns (bool);
    function decimals() external view returns (uint8);
    function balanceOf(address) external view returns (uint);
    function transferFrom(address sender, address recipient, uint amount) external returns (bool);
    function approve(address spender, uint value) external returns (bool);
}

interface ve {
    function token() external view returns (address);
    function balanceOfAtTime(address, uint) external view returns (uint);
}

interface IBaseV1Factory {
    function isPair(address) external view returns (bool);
}


abstract contract RewardBase {
    uint constant DURATION = 7 days; // rewards are released over 7 days
    uint constant PRECISION = 10 ** 18;

    address[] public incentives; // array of incentives for a given gauge/bribe
    mapping(address => bool) public isIncentive; // confirms if the incentive is currently valid for the gauge/bribe

    // default snx staking contract implementation
    mapping(address => uint) public rewardRate;
    mapping(address => uint) public periodFinish;
    mapping(address => uint) public lastUpdateTime;
    mapping(address => uint) public rewardPerTokenStored;

    mapping(address => mapping(address => uint)) public userRewardPerTokenPaid;
    mapping(address => mapping(address => uint)) public rewards;

    uint public totalSupply;
    mapping(address => uint) public balanceOf;

    // simple re-entrancy check
    uint _unlocked = 1;
    modifier lock() {
        require(_unlocked == 1);
        _unlocked = 0;
        _;
        _unlocked = 1;
    }

    function incentivesLength() external view returns (uint) {
        return incentives.length;
    }

    // returns the last time the reward was modified or periodFinish if the reward has ended
    function lastTimeRewardApplicable(address token) public view returns (uint) {
        return Math.min(block.timestamp, periodFinish[token]);
    }

    // how to calculate the reward given per token "staked" (or voted for bribes)
    function rewardPerToken(address token) public virtual view returns (uint);

    // how to calculate the total earnings of an address for a given token
    function earned(address token, address account) public virtual view returns (uint);

    // total amount of rewards returned for the 7 day duration
    function getRewardForDuration(address token) external view returns (uint) {
        return rewardRate[token] * DURATION;
    }

    // allows a user to claim rewards for a given token
    function getReward(address token) public lock updateReward(token, msg.sender) {
        uint _reward = rewards[token][msg.sender];
        rewards[token][msg.sender] = 0;
        _safeTransfer(token, msg.sender, _reward);
    }

    // used to notify a gauge/bribe of a given reward, this can create griefing attacks by extending rewards
    // TODO: rework to weekly resets, _updatePeriod as per v1 bribes
    function notifyRewardAmount(address token, uint amount) external lock updateReward(token, address(0)) returns (bool) {
        if (block.timestamp >= periodFinish[token]) {
            _safeTransferFrom(token, msg.sender, address(this), amount);
            rewardRate[token] = amount / DURATION;
        } else {
            uint _remaining = periodFinish[token] - block.timestamp;
            uint _left = _remaining * rewardRate[token];
            if (amount < _left) {
              return false; // don't revert to help distribute run through its tokens
            }
            _safeTransferFrom(token, msg.sender, address(this), amount);
            rewardRate[token] = (amount + _left) / DURATION;
        }

        lastUpdateTime[token] = block.timestamp;
        periodFinish[token] = block.timestamp + DURATION;

        // if it is a new incentive, add it to the stack
        if (isIncentive[token] == false) {
            isIncentive[token] = true;
            incentives.push(token);
        }
        return true;
    }

    modifier updateReward(address token, address account) virtual;

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

// Gauges are used to incentivize pools, they emit reward tokens over 7 days for staked LP tokens
// Nuance: getReward must be called at least once for tokens other than incentive[0] to start accrueing rewards
contract Gauge is RewardBase {

    address public immutable stake; // the LP token that needs to be staked for rewards
    address immutable _ve; // the ve token used for gauges

    uint public derivedSupply;
    mapping(address => uint) public derivedBalances;

    constructor(address _stake) {
        stake = _stake;
        address __ve = BaseV1Gauges(msg.sender)._ve();
        _ve = __ve;
        incentives.push(ve(__ve).token()); // assume the first incentive is the same token that creates ve
    }

    function rewardPerToken(address token) public override view returns (uint) {
        if (totalSupply == 0) {
            return rewardPerTokenStored[token];
        } // derivedSupply is used instead of totalSupply to modify for ve-BOOST
        return rewardPerTokenStored[token] + ((lastTimeRewardApplicable(token) - lastUpdateTime[token]) * rewardRate[token] * PRECISION / derivedSupply);
    }

    // used to update an account internally and externally, since ve decays over times, an address could have 0 balance but still register here
    function kick(address account) public {
        uint _derivedBalance = derivedBalances[account];
        derivedSupply -= _derivedBalance;
        _derivedBalance = derivedBalance(account);
        derivedBalances[account] = _derivedBalance;
        derivedSupply += _derivedBalance;
    }

    function derivedBalance(address account) public view returns (uint) {
        uint _balance = balanceOf[account];
        uint _derived = _balance * 40 / 100;
        uint _adjusted = (totalSupply * ve(_ve).balanceOfAtTime(account, block.timestamp) / erc20(_ve).totalSupply()) * 60 / 100;
        return Math.min(_derived + _adjusted, _balance);
    }

    function earned(address token, address account) public override view returns (uint) {
        return (derivedBalances[account] * (rewardPerToken(token) - userRewardPerTokenPaid[token][account]) / PRECISION) + rewards[token][account];
    }

    // Current commented out since hardhat doesn't support testing with function overloading

    /*function deposit() external {
        _deposit(erc20(stake).balanceOf(msg.sender), msg.sender);
    }

    function deposit(uint amount) external {
        _deposit(amount, msg.sender);
    }*/

    function deposit(uint amount, address account) external {
        _deposit(amount, account);
    }

    function _deposit(uint amount, address account) internal lock updateReward(incentives[0], account) {
        _safeTransferFrom(stake, account, address(this), amount);
        totalSupply += amount;
        balanceOf[account] += amount;
    }

    function withdraw() external {
        _withdraw(balanceOf[msg.sender]);
    }

    function withdraw(uint amount) external {
        _withdraw(amount);
    }

    function _withdraw(uint amount) internal lock updateReward(incentives[0], msg.sender) {
        totalSupply -= amount;
        balanceOf[msg.sender] -= amount;
        _safeTransfer(stake, msg.sender, amount);
    }

    function exit() external {
        if (balanceOf[msg.sender] > 0) _withdraw(balanceOf[msg.sender]); // include balance 0 check for tokens that might revert on 0 balance (assuming withdraw > exit)
        getReward(incentives[0]);
    }

    modifier updateReward(address token, address account) override {
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
}

// Bribes pay out rewards for a given pool based on the votes that were received from the user (goes hand in hand with BaseV1Gauges.vote())
// Nuance: users must call updateReward after they voted for a given bribe
contract Bribe is RewardBase {

    address immutable factory; // only factory can modify balances (since it only happens on vote())

    constructor() {
        factory = msg.sender;
    }

    function rewardPerToken(address token) public override view returns (uint) {
        if (totalSupply == 0) {
            return rewardPerTokenStored[token];
        }
        return rewardPerTokenStored[token] + ((lastTimeRewardApplicable(token) - lastUpdateTime[token]) * rewardRate[token] * PRECISION / totalSupply);
    }

    function earned(address token, address account) public override view returns (uint) {
        return (balanceOf[account] * (rewardPerToken(token) - userRewardPerTokenPaid[token][account]) / PRECISION) + rewards[token][account];
    }

    // This is an external function, but internal notation is used since it can only be called "internally" from BaseV1Gauges
    function _deposit(uint amount, address account) external {
        require(msg.sender == factory);
        totalSupply += amount;
        balanceOf[account] += amount;
    }

    function _withdraw(uint amount, address account) external {
        require(msg.sender == factory);
        totalSupply -= amount;
        balanceOf[account] -= amount;
    }

    modifier updateReward(address token, address account) override {
        rewardPerTokenStored[token] = rewardPerToken(token);
        lastUpdateTime[token] = lastTimeRewardApplicable(token);
        if (account != address(0)) {
            rewards[token][account] = earned(token, account);
            userRewardPerTokenPaid[token][account] = rewardPerTokenStored[token];
        }
        _;
    }
}

contract BaseV1Gauges {

    address public immutable _ve; // the ve token that governs these contracts
    address public immutable factory; // the BaseV1Factory

    uint public totalWeight; // total voting weight

    // simple re-entrancy check
    uint _unlocked = 1;
    modifier lock() {
        require(_unlocked == 1);
        _unlocked = 0;
        _;
        _unlocked = 1;
    }

    address[] internal _pools; // all pools viable for incentives
    mapping(address => address) public gauges; // pool => gauge
    mapping(address => address) public bribes; // gauge => bribe
    mapping(address => uint) public weights; // pool => weight
    mapping(address => mapping(address => uint)) public votes; // msg.sender => votes
    mapping(address => address[]) public poolVote;// msg.sender => pools
    mapping(address => uint) public usedWeights;  // msg.sender => total voting weight of user

    function pools() external view returns (address[] memory) {
        return _pools;
    }

    constructor(address __ve, address _factory) {
        _ve = __ve;
        factory = _factory;
    }

    function reset() external {
        _reset(msg.sender);
    }

    function _reset(address _owner) internal {
        address[] storage _poolVote = poolVote[_owner];
        uint _poolVoteCnt = _poolVote.length;

        for (uint i = 0; i < _poolVoteCnt; i ++) {
            address _pool = _poolVote[i];
            uint _votes = votes[_owner][_pool];

            if (_votes > 0) {
                totalWeight -= _votes;
                weights[_pool] -= _votes;
                votes[_owner][_pool] = 0;
                Bribe(bribes[gauges[_pool]])._withdraw(_votes, _owner);
            }
        }

        delete poolVote[_owner];
    }

    function poke(address _owner) public {
        address[] memory _poolVote = poolVote[_owner];
        uint _poolCnt = _poolVote.length;
        uint[] memory _weights = new uint[](_poolCnt);

        uint _prevUsedWeight = usedWeights[_owner];
        uint _weight = ve(_ve).balanceOfAtTime(_owner, block.timestamp);

        for (uint i = 0; i < _poolCnt; i ++) {
            uint _prevWeight = votes[_owner][_poolVote[i]];
            _weights[i] = _prevWeight * _weight / _prevUsedWeight;
        }

        _vote(_owner, _poolVote, _weights);
    }

    function _vote(address _owner, address[] memory _poolVote, uint[] memory _weights) internal {
        _reset(_owner);
        uint _poolCnt = _poolVote.length;
        uint _weight = ve(_ve).balanceOfAtTime(_owner, block.timestamp);
        uint _totalVoteWeight = 0;
        uint _usedWeight = 0;

        for (uint i = 0; i < _poolCnt; i ++) {
            _totalVoteWeight += _weights[i];
        }

        for (uint i = 0; i < _poolCnt; i ++) {
            address _pool = _poolVote[i];
            address _gauge = gauges[_pool];
            uint _poolWeight = _weights[i] * _weight / _totalVoteWeight;

            if (_gauge != address(0x0)) {
                _usedWeight += _poolWeight;
                totalWeight += _poolWeight;
                weights[_pool] += _poolWeight;
                poolVote[_owner].push(_pool);
                votes[_owner][_pool] = _poolWeight;
                Bribe(bribes[gauges[_pool]])._deposit(_poolWeight, _owner);
            }
        }

        usedWeights[_owner] = _usedWeight;
    }

    function vote(address[] calldata _poolVote, uint[] calldata _weights) external {
        require(_poolVote.length == _weights.length);
        _vote(msg.sender, _poolVote, _weights);
    }

    function createGauge(address _pool) external returns (address) {
        require(gauges[_pool] == address(0x0), "exists");
        require(IBaseV1Factory(factory).isPair(_pool), "!_pool");
        address _gauge = address(new Gauge(_pool));
        address _bribe = address(new Bribe());
        bribes[_gauge] = _bribe;
        gauges[_pool] = _gauge;
        _pools.push(_pool);
        return _gauge;
    }

    function length() external view returns (uint) {
        return _pools.length;
    }

    function distribute(address token) external lock {
        uint _balance = erc20(token).balanceOf(address(this));
        if (_balance > 0 && totalWeight > 0) {
            uint _totalWeight = totalWeight;
            for (uint x = 0; x < _pools.length; x++) {
              uint _reward = _balance * weights[_pools[x]] / _totalWeight;
              if (_reward > 0) {
                  address _gauge = gauges[_pools[x]];

                  erc20(token).approve(_gauge, 0); // first set to 0, this helps reset some non-standard tokens
                  erc20(token).approve(_gauge, _reward);
                  Gauge(_gauge).notifyRewardAmount(token, _reward); // can return false, will simply not distribute tokens
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
