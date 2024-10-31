// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Import OpenZeppelin Contracts v4.9.2
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

/// @title OLMRewardToken Contract
/// @notice ERC20 token awarded when users send ETH to the contract
contract OLMRewardToken is ERC20, Ownable {
    constructor() ERC20("OLM Reward Token", "OLMRT") {}

    /// @notice Mints new tokens to a specified address
    /// @param to The address to mint tokens to
    /// @param amount The amount of tokens to mint
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }
}
