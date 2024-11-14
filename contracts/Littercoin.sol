// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Import OpenZeppelin Contracts v4.9.2
import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { ERC721Enumerable } from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

// Import Dependencies
import { MerchantToken } from "./MerchantToken.sol";
import { OLMRewardToken } from "./OLMRewardToken.sol";

import "hardhat/console.sol";
import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

contract Littercoin is ERC721, ERC721Enumerable, Ownable, ReentrancyGuard {

    using Counters for Counters.Counter;

    // ID of the next Littercoin to be minted
    Counters.Counter private _tokenCounter;

    // Used nonces for preventing replay attacks
    mapping(uint256 => bool) public usedNonces;

    // Mapping to track the number of transactions for each Littercoin NFT
    mapping(uint256 => uint256) public transferCount;

    // Define a limit for the number of transactions each Littercoin can have
    uint256 public constant MAX_TRANSACTIONS = 3;

    // OLM Reward Token
    OLMRewardToken public rewardToken;

    // Merchant Token
    MerchantToken public merchantToken;

    // Chainlink Price Feed
    AggregatorV3Interface internal priceFeed;

    /// @notice Contract constructor
    constructor (address _priceFeed) ERC721("Littercoin", "LITTERX") {
        // Deploy the Reward Token and transfer ownership to this contract
        rewardToken = new OLMRewardToken();
        rewardToken.transferOwnership(address(this));

        // Deploy the Merchant Token
        merchantToken = new MerchantToken();
        merchantToken.transferOwnership(msg.sender);

        // Set up Chainlink Price Feed (ETH/USD on mainnet)
        priceFeed = AggregatorV3Interface(_priceFeed);
    }

    /// @notice Event emitted when a user mints Littercoin
    event Mint(address indexed user, uint256 amount);

    /// @notice Event emitted when a valid Merchant Token Holder burns Littercoin for ETH
    event BurnLittercoin (address indexed user, uint256 tokensToBurn, uint256 ethAmount);

    /// @notice Event emitted when a user is rewarded OLM Reward Tokens
    event Reward (address indexed user, uint256 rewardAmount);

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
    /// @param expiry The expiry time of the signature
    /// @param signature The signature provided by the backend
    function mint (uint256 amount, uint256 nonce, uint256 expiry, bytes memory signature) external {
        require(amount > 0, "Amount must be greater than zero");
        require(block.timestamp <= expiry, "Signature has expired");
        require(!usedNonces[nonce], "Nonce already used");

        // Update nonce as used
        usedNonces[nonce] = true;

        // Construct the hash to be signed by the backend
        bytes32 messageHash = keccak256(abi.encodePacked(msg.sender, amount, nonce, expiry));
        require(ECDSA.recover(ECDSA.toEthSignedMessageHash(messageHash), signature) == owner(), "Invalid signature");
        bytes32 ethSignedMessageHash = getEthSignedMessageHash(messageHash);

        // Verify the signature
        address signer = recoverSigner(ethSignedMessageHash, signature);
        require(signer == owner(), "Invalid signature");

        // Mint tokens for the user
        for (uint256 i = 0; i < amount; i++) {
            _tokenCounter.increment();
            uint256 tokenId = _tokenCounter.current();

            // Mint tokens to the user
            _safeMint(msg.sender, tokenId);

            // Initialize the transfer count for the newly minted NFT
            transferCount[tokenId] = 0;
        }

        emit Mint(msg.sender, amount);
    }

    function getEthSignedMessageHash (bytes32 _messageHash) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", _messageHash));
    }

    function recoverSigner (bytes32 _ethSignedMessageHash, bytes memory _signature) internal pure returns (address) {
        (bytes32 r, bytes32 s, uint8 v) = splitSignature(_signature);

        return ecrecover(_ethSignedMessageHash, v, r, s);
    }

    function splitSignature (bytes memory sig) internal pure returns (bytes32 r, bytes32 s, uint8 v) {
        require(sig.length == 65, "Invalid signature length");

        assembly {
            r := mload(add(sig, 32))
            s := mload(add(sig, 64))
            v := byte(0, mload(add(sig, 96)))
        }
    }

    /// @notice Track each token transfer and increment the count
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId,
        uint256 batchSize
    ) internal override(ERC721, ERC721Enumerable) {
        super._beforeTokenTransfer(from, to, tokenId, batchSize);

        // Increment the transfer count when the token is transferred
        if (from != address(0) && to != address(0)) {
            transferCount[tokenId] += 1;
            require(transferCount[tokenId] <= MAX_TRANSACTIONS, "Token transfer limit exceeded.");
        }
    }

    // Override the supportsInterface function to include ERC721Enumerable
    function supportsInterface (bytes4 interfaceId) public view override(ERC721, ERC721Enumerable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    /// @notice Burn multiple Littercoin NFTs and transfer the average ETH per NFT to the merchant
    /// @param tokenIds The IDs of the Littercoin NFTs to redeem
    function burnLittercoin (uint256[] calldata tokenIds) external nonReentrant {
        require(merchantToken.hasValidMerchantToken(msg.sender), "Must hold a valid Merchant Token.");

        // Check for Littercoin to burn
        uint256 numTokens = tokenIds.length;
        require(numTokens > 0, "No tokens provided.");

        uint256 totalSupply = totalSupply();
        require(totalSupply > 0, "No tokens in circulation.");

        // Ensure there is more than 0 ETH in the contract
        uint256 contractBalance = address(this).balance;
        require(contractBalance > 0, "Not enough ETH in contract.");

        // Validate all tokens
        for (uint256 i = 0; i < numTokens; i++) {
            uint256 tokenId = tokenIds[i];
            require(ownerOf(tokenId) == msg.sender, "Caller must own all tokens being redeemed.");
            require(transferCount[tokenId] <= 2, "Token has been invalidated due to too many transfers.");
            _burn(tokenId);
        }

        // Calculate the total number of eligible tokens to redeem
        uint256 totalEthToTransfer = (contractBalance * numTokens) / totalSupply;

        // Transfer the total ETH to the caller with reentrancy protection
        (bool success, ) = payable(msg.sender).call{value: totalEthToTransfer}("");
        require(success, "Transfer failed");

        emit BurnLittercoin(msg.sender, numTokens, totalEthToTransfer);
    }

    /// @notice Accepts ETH and rewards OLMRewardTokens based on the amount
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

    // @notice Get the current token ID
    function getCurrentTokenId () external view returns (uint256) {
        return _tokenCounter.current();
    }
}
