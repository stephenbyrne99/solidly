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
    function token() external view returns (address);
    function totalSupply() external view returns (uint);
}

interface underlying {
    function approve(address spender, uint value) external returns (bool);
    function mint(address, uint) external;
    function totalSupply() external view returns (uint);
}

interface gauge_proxy {
    function notifyRewardAmount(uint amount) external;
}

interface ve_dist {
    function checkpoint_token() external;
    function checkpoint_total_supply() external;
}

// codifies the minting rules as per ve(3,3), abstracted from the token to support any token that allows minting

contract BaseV1Minter {
    uint constant week = 86400 * 7; // allows minting once per week (reset every Thursday 00:00 UTC)
    uint constant emission = 4; // 0.4% per week target emission
    uint constant base = 100;
    underlying public immutable _token;
    gauge_proxy public immutable _gauge_proxy;
    ve public immutable _ve;
    ve_dist public immutable _ve_dist;
    uint public available;
    uint public active_period;

    constructor(
      //uint _available, // the minting target halfway point, assuming 500mm
      address __gauge_proxy, // the voting & distribution system
      address  __ve, // the ve(3,3) system that will be locked into
      address __ve_dist // the distribution system that ensures users aren't diluted
    ) {
        _token = underlying(ve(__ve).token());
        available = 500000000e18;//_available;
        _gauge_proxy = gauge_proxy(__gauge_proxy);
        _ve = ve(__ve);
        _ve_dist = ve_dist(__ve_dist);

    }

    // calculate circulating supply as total token supply - locked supply
    function circulating_supply() public view returns (uint) {
        return _token.totalSupply() - _ve.totalSupply();
    }

    // emission calculation is 0.4% of available supply to mint adjusted by circulating / total supply
    function calculate_emission() public view returns (uint) {
        return available * emission / base * circulating_supply() / _token.totalSupply();
    }

    // weekly emission takes the max of calculated (aka target) emission versus circulating tail end emission
    function weekly_emission() public view returns (uint) {
        return Math.max(calculate_emission(), circulating_emission());
    }

    // calculates tail end (infinity) emissions as 0.4% of total supply
    function circulating_emission() public view returns (uint) {
        return circulating_supply() * emission / base;
    }

    // calculate inflation and adjust ve balances accordingly
    function calculate_growth(uint _minted) public view returns (uint) {
        return _ve.totalSupply() * _minted / circulating_supply();
    }

    // update period can only be called once per cycle (1 week)
    function update_period() external returns (uint) {
        uint _period = active_period;
        if (block.timestamp >= _period + week) { // only trigger if new week
            _period = block.timestamp / week * week;
            active_period = _period;
            uint _amount = weekly_emission();
            if (_amount <= available) {
                available -= _amount;
            }

            _token.mint(address(this), _amount); // mint weekly emission to gauge proxy (handles voting and distribution)
            _token.approve(address(_gauge_proxy), _amount);
            _gauge_proxy.notifyRewardAmount(_amount);

            _token.mint(address(_ve_dist), calculate_growth(_amount)); // mint inflation for staked users based on their % balance
            _ve_dist.checkpoint_token(); // checkpoint token balance that was just minted in ve_dist
            _ve_dist.checkpoint_total_supply(); // checkpoint supply
        }
        return _period;
    }

}
