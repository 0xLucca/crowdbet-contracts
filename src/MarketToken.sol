// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title MarketToken
 * @dev ERC20 token for market positions
 */

import "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract MarketToken is ERC20 {
    address public immutable market;
    
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        market = msg.sender;
    }
    
    function mint(address to, uint256 amount) external {
        require(msg.sender == market, "Only market can mint");
        _mint(to, amount);
    }
    
    function burn(address from, uint256 amount) external {
        require(msg.sender == market, "Only market can burn");
        _burn(from, amount);
    }
}