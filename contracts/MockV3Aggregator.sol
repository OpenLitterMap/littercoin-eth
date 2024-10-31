// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract MockV3Aggregator is AggregatorV3Interface, Ownable {
    int256 private price;
    uint8 private decimalsValue;

    constructor(uint8 _decimals, int256 _initialPrice) {
        decimalsValue = _decimals;
        price = _initialPrice;
    }

    // Implement `decimals` function from AggregatorV3Interface
    function decimals() external view override returns (uint8) {
        return decimalsValue;
    }

    // Implement `description` function from AggregatorV3Interface
    function description() external pure override returns (string memory) {
        return "Mock V3 Aggregator";
    }

    // Implement `version` function from AggregatorV3Interface
    function version() external pure override returns (uint256) {
        return 1;
    }

    // Implement `getRoundData` function from AggregatorV3Interface
    function getRoundData(uint80 _roundId)
    external
    view
    override
    returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    )
    {
        require(_roundId == 0, "Invalid round ID");
        return (0, price, block.timestamp, block.timestamp, 0);
    }

    // Implement `latestRoundData` function from AggregatorV3Interface
    function latestRoundData()
    external
    view
    override
    returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    )
    {
        return (0, price, block.timestamp, block.timestamp, 0);
    }

    // Custom function to set the price for testing
    function setPrice(int256 _price) external onlyOwner {
        price = _price;
    }

    function deployed () external pure returns (bool) {
        return true;
    }
}
