// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

/// @title OLMThankYouToken Contract
/// @notice ERC20 token awarded when users send ETH to the contract
contract OLMThankYouToken is ERC20, Ownable {
    constructor(address initialOwner) ERC20("OLM Thank You Token", "OLMTY") Ownable(initialOwner) {}

    /// @notice Mints new tokens to a specified address
    /// @param to The address to mint tokens to
    /// @param amount The amount of tokens to mint
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }
}
