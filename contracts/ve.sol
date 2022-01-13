// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.11;

contract ve {


    uint256 public totalSupply = 100e18;
    address immutable public token;
    constructor(address _token) {
        token = _token;
    }

    function balance(address account) external view returns (uint) {
        return 100e18;
    }

    function balanceOfNFT(uint tokenId, uint timestamp) external view returns (uint) {
        return 100e18;
    }

    function isApprovedOrOwner(address owner, uint _tokenId) external view returns (bool) {
        return true;
    }
}
