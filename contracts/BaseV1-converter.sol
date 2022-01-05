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

interface IStableV1Router01 {
    function getAmountsOut(uint amountIn, address[] memory path) external view returns (uint[] memory amounts);
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);
    function isPair(address) external view returns (bool);
}

contract StableV1Converter01 {

    address immutable public router;

    constructor(address _router) {
        router = _router;
    }

    function collectFees() external {

    }

}
