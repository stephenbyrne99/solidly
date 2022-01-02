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
    function locked__end(address) external view returns (uint);
    function deposit_for(address, uint) external;
    function token() external view returns (address);
    function get_adjusted_ve_balance(address, address) external view returns (uint);
}

interface StableV1Factory {
    function _ve() external view returns (address);
}


abstract contract RewardBase {
    uint constant DURATION = 7 days;
    uint constant PRECISION = 10 ** 18;
    uint constant MAXTIME = 4 * 365 * 86400;
    
    address[] public incentives;
    mapping(address => bool) public isIncentive;
    mapping(address => uint) public rewardRate;
    mapping(address => uint) public periodFinish;
    mapping(address => uint) public lastUpdateTime;
    mapping(address => uint) public rewardPerTokenStored;
    
    mapping(address => mapping(address => uint)) public userRewardPerTokenPaid;
    mapping(address => mapping(address => uint)) public rewards;

    uint public totalSupply;
    mapping(address => uint) public balanceOf;

    function incentivesLength() external view returns (uint) {
        return incentives.length;
    }

    function lastTimeRewardApplicable(address token) public view returns (uint) {
        return Math.min(block.timestamp, periodFinish[token]);
    }

    function rewardPerToken(address token) public virtual view returns (uint);

    function earned(address token, address account) public virtual view returns (uint);

    function getRewardForDuration(address token) external view returns (uint) {
        return rewardRate[token] * DURATION;
    }

    function getReward(address token) public updateReward(token, msg.sender) {
        uint _reward = rewards[token][msg.sender];
        rewards[token][msg.sender] = 0;
        _safeTransfer(token, msg.sender, _reward);
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

        if (isIncentive[token] == false) {
            isIncentive[token] = true;
            incentives.push(token);
        }
    }

    modifier updateReward(address token, address account) {
        rewardPerTokenStored[token] = rewardPerToken(token);
        lastUpdateTime[token] = lastTimeRewardApplicable(token);
        if (account != address(0)) {
            rewards[token][account] = earned(token, account);
            userRewardPerTokenPaid[token][account] = rewardPerTokenStored[token];
        }
        _;
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

contract Gauge is RewardBase {
    
    address public immutable stake;
    address immutable _ve;
    
    uint public derivedSupply;
    mapping(address => uint) public derivedBalances;
    
    constructor(address _stake) {
        stake = _stake;
        address __ve = StableV1Factory(msg.sender)._ve();
        _ve = __ve;
        incentives[0] = ve(__ve).token();
    }

    function rewardPerToken(address token) public override view returns (uint) {
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

    function earned(address token, address account) public override view returns (uint) {
        return (derivedBalances[account] * (rewardPerToken(token) - userRewardPerTokenPaid[token][account]) / PRECISION) + rewards[token][account];
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
    
    function _deposit(uint amount, address account) internal updateReward(incentives[0], account) {
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
    
    function _withdraw(uint amount) internal updateReward(incentives[0], msg.sender) {
        totalSupply -= amount;
        balanceOf[msg.sender] -= amount;
        _safeTransfer(stake, msg.sender, amount);
    }

    function exit() external {
       _withdraw(balanceOf[msg.sender]);
        getReward(incentives[0]);
    }
}

contract Bribe is RewardBase {

    address immutable factory;

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
}

contract StableV1Gauges {
    

    address public immutable _ve;
    address public immutable base;
    address constant ZERO_ADDRESS = 0x0000000000000000000000000000000000000000;
    
    uint public totalWeight;
    
    address public gov;
    address public nextgov;
    uint public commitgov;
    uint public constant delay = 1 days;
    
    address[] internal _tokens;
    mapping(address => address) public gauges; // pair => gauge
    mapping(address => address) public bribes; // gauge => bribe
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
                Bribe(bribes[gauges[_token]])._withdraw(_votes, _owner);
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
                Bribe(bribes[gauges[_token]])._deposit(_tokenWeight, _owner);
            }
        }

        usedWeights[_owner] = _usedWeight;
    }
    
    function vote(address[] calldata _tokenVote, uint[] calldata _weights) external {
        require(_tokenVote.length == _weights.length);
        _vote(msg.sender, _tokenVote, _weights);
    }
    
    function addGauge(address _token) external {
        require(gauges[_token] == address(0x0), "exists");
        address _gauge = address(new Gauge(_token));
        address _bribe = address(new Bribe());
        bribes[_gauge] = _bribe;
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