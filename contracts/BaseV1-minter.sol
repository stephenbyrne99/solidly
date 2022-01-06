// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.11;

library Math {
    function max(uint a, uint b) internal pure returns (uint) {
        return a >= b ? a : b;
    }
    function min(uint a, uint b) internal pure returns (uint) {
        return a < b ? a : b;
    }
}

interface ve {
    function totalSupply() external view returns (uint);
}

interface token {
    function mint(address, uint) external;
    function totalSupply() external view returns (uint);
}

interface gauge_proxy {
    function distribute() external;
}

interface ve_dist {
    function checkpoint_token() external;
    function checkpoint_total_supply() external;
}

contract minter {
    uint constant week = 86400 * 7;
    uint constant emission = 4;
    uint constant base = 100;
    token public immutable _token;
    gauge_proxy public immutable _gauge_proxy;
    ve public immutable _ve;
    ve_dist public immutable _ve_dist;
    uint public available;
    uint public active_period;

    constructor(
      address __token,
      uint _available,
      address __gauge_proxy,
      address  __ve,
      address __ve_dist
    ) {
        _token = token(__token);
        available = _available;
        _gauge_proxy = gauge_proxy(__gauge_proxy);
        _ve = ve(__ve);
        _ve_dist = ve_dist(__ve_dist);
    }

    function circulating_supply() public view returns (uint) {
        return _token.totalSupply() - _ve.totalSupply();
    }

    function calculate_emission() public view returns (uint) {
        return available * emission / base * circulating_supply() / _token.totalSupply();
    }

    function weekly_emission() public view returns (uint) {
        return Math.max(calculate_emission(), circulating_emission());
    }

    function circulating_emission() public view returns (uint) {
        return circulating_supply() * emission / base;
    }

    function calculate_growth(uint _minted) public view returns (uint) {
        return _ve.totalSupply() * _minted / circulating_supply();
    }

    function update_period() external returns (uint) {
        uint _period = active_period;
        if (block.timestamp >= _period + week) {
            _period = block.timestamp / week * week;
            active_period = _period;
            uint _amount = weekly_emission();
            if (_amount <= available) {
                available -= _amount;
            }

            _token.mint(address(_gauge_proxy), _amount);
            _token.mint(address(_ve_dist), calculate_growth(_amount));
            _ve_dist.checkpoint_token();
            _ve_dist.checkpoint_total_supply();
        }
        return _period;
    }

}
