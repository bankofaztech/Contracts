// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract BankOfAztech is ERC20 {
    uint256 private constant MAX_SUPPLY = 33000000 * 10**18; // 33 milyon token (18 decimals ile)
    
    constructor() ERC20("BankOfAztech", "BOFA") {
        _mint(msg.sender, MAX_SUPPLY);
    }
} 
