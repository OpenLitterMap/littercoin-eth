// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Import OpenZeppelin Contracts v4.9.2
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { ERC721Enumerable } from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";

// Import Dependencies
import { MerchantToken } from "./MerchantToken.sol";
import { OLMRewardToken } from "./OLMRewardToken.sol";

import "hardhat/console.sol";
import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

contract Littercoin is ERC20, Ownable, ReentrancyGuard {
    // Mapping to track the total amount minted by each user
    mapping(address => uint256) public littercoinAmounts;

    // OLM Reward Token
    OLMRewardToken public rewardToken;

    // Merchant Token
    MerchantToken public merchantToken;

    // Chainlink Price Feed
    AggregatorV3Interface internal priceFeed;

    /// @notice Contract constructor
    constructor (address _priceFeed) ERC20("Littercoin", "LITTERX") {
        // Deploy the Reward Token and transfer ownership to this contract
        rewardToken = new OLMRewardToken();
        rewardToken.transferOwnership(address(this));

        // Deploy the Merchant Token
        merchantToken = new MerchantToken();
        merchantToken.transferOwnership(msg.sender);

        // Set up Chainlink Price Feed (ETH/USD on mainnet)
        priceFeed = AggregatorV3Interface(_priceFeed);
    }

    /// @notice Getter function for rewardToken address
    /// @notice - only needed for testing
    function getRewardTokenAddress() external view returns (address) {
        return address(rewardToken);
    }

    /// @notice Getter function for merchantToken address
    /// @notice - only needed for testing
    function getMerchantTokenAddress() external view returns (address) {
        return address(merchantToken);
    }

    /// @notice Users can mint Littercoin tokens
    /// @param amount The amount of tokens to mint
    /// @param nonce The nonce provided by the backend
    /// @param signature The signature provided by the backend
    function mint (uint256 amount, uint256 nonce, bytes memory signature) external {
        require(amount > 0, "Amount must be greater than zero");

        // The backend provides a signed message
        // Construct the hash to be signed
        bytes32 messageHash = keccak256(abi.encodePacked(msg.sender, amount, nonce));
        bytes32 ethSignedMessageHash = getEthSignedMessageHash(messageHash);

        // Verify the signature
        address signer = recoverSigner(ethSignedMessageHash, signature);
        require(signer == owner(), "Invalid signature");

        // Update the minted amount for the user
        littercoinAmounts[msg.sender] += amount;

        // Mint tokens to the user
        _mint(msg.sender, amount);

        emit Mint(msg.sender, amount);
    }

    function getEthSignedMessageHash (bytes32 _messageHash) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", _messageHash));
    }

    function recoverSigner (bytes32 _ethSignedMessageHash, bytes memory _signature) internal pure returns (address) {
        (bytes32 r, bytes32 s, uint8 v) = splitSignature(_signature);

        return ecrecover(_ethSignedMessageHash, v, r, s);
    }

    function splitSignature(bytes memory sig) internal pure returns (bytes32 r, bytes32 s, uint8 v) {
        require(sig.length == 65, "Invalid signature length");

        assembly {
            r := mload(add(sig, 32))
            s := mload(add(sig, 64))
            v := byte(0, mload(add(sig, 96)))
        }
    }

    /// @notice Event emitted when a user mints Littercoin
    event Mint(address indexed user, uint256 amount);
    
    /// @notice Allows users with a Merchant Token to send Littercoin in and get ETH out
    /// @param amount The amount of Littercoin to redeem
    function redeemLittercoin (uint256 amount) external nonReentrant {
        require(merchantToken.balanceOf(msg.sender) > 0, "Must hold a Merchant Token");
        require(merchantToken.hasValidMerchantToken(msg.sender), "Must hold a Valid Merchant Token");
        require(balanceOf(msg.sender) >= amount, "Insufficient Littercoin balance");
        require(address(this).balance >= amount, "Not enough ETH in contract");

        // Transfer Littercoin from user to contract
        _transfer(msg.sender, address(this), amount);

        uint256 ethToTransfer = amount;

        // Transfer ETH to the user with reentrancy protection
        (bool success, ) = payable(msg.sender).call{value: ethToTransfer}("");
        require(success, "Transfer failed");

        emit Redeem(msg.sender, amount, amount);
    }

    /// @notice Event emitted when a user redeems Littercoin for ETH
    event Redeem (address indexed user, uint256 littercoinAmount, uint256 ethAmount);

    /// @notice Accepts ETH and rewards OLM Reward Tokens based on the amount
    receive () external payable {
        uint256 ethAmount = msg.value;

        // Get the latest ETH/USD price
        (, int256 price, , , ) = priceFeed.latestRoundData();
        require(price > 0, "Invalid price from Chainlink");

        // Convert price to uint256 and get reward amount
        // assume $2000 for testing
        // Assuming the price feed has 8 decimals
        // Convert price to uint256 and get ethPriceUsd (the price of 1 ETH in USD)
        uint256 ethPriceUsd = uint256(price); // The price from Chainlink has 8 decimals

        // Calculate the number of reward tokens to mint
        // ethPriceUsd has 8 decimals, so divide by 10^8 to get the actual USD value
        // ethAmount is in wei (10^18), so divide by 10^18 to convert to ETH
        // rewardAmount = ethAmount (in USD) * (1 OLMRewardToken / 1 USD)
        uint256 rewardAmount = (ethAmount * ethPriceUsd) / 1e26;

        // Mint OLM Reward Tokens to the sender
        rewardToken.mint(msg.sender, rewardAmount);

        emit Reward(msg.sender, rewardAmount);
    }

    /// @notice Event emitted when a user is rewarded OLM Reward Tokens
    event Reward (address indexed user, uint256 rewardAmount);
}
