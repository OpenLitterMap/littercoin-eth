// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Import OpenZeppelin Contracts v4.9.2
import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { ERC721Enumerable } from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";

// Import Dependencies
import { MerchantToken } from "./MerchantToken.sol";
import { OLMRewardToken } from "./OLMRewardToken.sol";

import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

contract Littercoin is ERC721, ERC721Enumerable, Ownable, ReentrancyGuard, Pausable, EIP712 {

    using Counters for Counters.Counter;

    // ID of the next Littercoin to be minted
    Counters.Counter private _tokenCounter;

    // Used nonces for preventing replay attacks
    mapping(uint256 => bool) public usedNonces;

    // Mapping to track the number of transactions for each Littercoin NFT
    mapping(uint256 => uint8) public transferCount;

    // Define a limit for the number of transactions each Littercoin can have
    uint256 public constant MAX_TRANSACTIONS = 3;

    // Define a limit for the number of Littercoin tokens that can be minted at once
    uint256 public constant MAX_MINT_AMOUNT = 10;

    // OLM Reward Token
    OLMRewardToken public rewardToken;

    // Merchant Token
    MerchantToken public merchantToken;

    // Chainlink Price Feed
    AggregatorV3Interface internal priceFeed;

    // EIP-712 Domain Separator and Type Hash
    bytes32 private constant MINT_TYPEHASH = keccak256("Mint(address user,uint256 amount,uint256 nonce,uint256 expiry)");

    /// @notice Contract constructor
    constructor (address _priceFeed) ERC721("Littercoin", "LITTERX") EIP712("Littercoin", "1") {
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

    /// @notice
    function _hashMint (address user, uint256 amount, uint256 nonce, uint256 expiry) internal view returns (bytes32) {
        return _hashTypedDataV4(
            keccak256(
                abi.encode(
                    keccak256("Mint(address user,uint256 amount,uint256 nonce,uint256 expiry)"),
                    user,
                    amount,
                    nonce,
                    expiry
                )
            )
        );
    }

    /// @notice Users can mint Littercoin tokens
    /// @param amount The amount of tokens to mint
    /// @param nonce The nonce provided by the backend
    /// @param expiry The expiry time of the signature
    /// @param signature The signature provided by the backend
    function mint (uint256 amount, uint256 nonce, uint256 expiry, bytes memory signature) external whenNotPaused {
        require(amount > 0 && amount <= MAX_MINT_AMOUNT, "Amount must be greater than zero and less than 10");
        require(block.timestamp <= expiry, "Signature has expired");
        require(!usedNonces[nonce], "Nonce already used");

        // Update nonce as used
        usedNonces[nonce] = true;

        // Construct the EIP-712 hash to be signed by the backend
        bytes32 digest = _hashMint(msg.sender, amount, nonce, expiry);
        address signer = ECDSA.recover(digest, signature);
        require(signer == owner(), "Invalid signature");

        // Mint tokens for the user
        for (uint256 i = 0; i < amount; i++) {
            _tokenCounter.increment();
            uint256 tokenId = _tokenCounter.current();

            // Mint tokens to the user
            _safeMint(msg.sender, tokenId);

            // Initialize the transfer count for the newly minted NFT
            transferCount[tokenId] = 1;
        }

        emit Mint(msg.sender, amount);
    }

    /// @notice Burn multiple Littercoin NFTs and transfer the average ETH per NFT to the merchant
    /// @param tokenIds The IDs of the Littercoin NFTs to redeem
    function burnLittercoin (uint256[] calldata tokenIds) external nonReentrant whenNotPaused {
        require(merchantToken.hasValidMerchantToken(msg.sender), "Must hold a valid Merchant Token.");

        // Check for Littercoin to burn
        uint256 numTokens = tokenIds.length;
        require(numTokens > 0, "No tokens provided.");

        uint256 totalSupply = totalSupply();
        require(totalSupply > 0, "No tokens in circulation.");

        // Ensure there is more than 0 ETH in the contract
        uint256 contractBalance = address(this).balance;
        require(contractBalance > 0, "Not enough ETH in contract.");

        // Validate all and process each token
        for (uint256 i = 0; i < numTokens; i++) {
            uint256 tokenId = tokenIds[i];

            require(ownerOf(tokenId) == msg.sender, "Caller must own all tokens being redeemed.");
            require(transferCount[tokenId] == 2, "Token is not in a valid state to burn.");

            _burn(tokenId);

            delete transferCount[tokenId];
        }

        // Calculate the total number of eligible tokens to redeem
        uint256 totalEthToTransfer = (contractBalance * numTokens) / totalSupply;

        // Transfer the total ETH to the caller with reentrancy protection
        (bool success, ) = payable(msg.sender).call{value: totalEthToTransfer}("");
        require(success, "Transfer failed");

        emit BurnLittercoin(msg.sender, numTokens, totalEthToTransfer);
    }

    /// @notice Accepts ETH and rewards OLMRewardTokens based on the amount
    receive () external payable nonReentrant {
        require(!paused(), "Pausable: paused");
        uint256 ethAmount = msg.value;

        // Get the latest ETH/USD price
        (, int256 price, , , ) = priceFeed.latestRoundData();
        require(price > 0, "Invalid price from Chainlink");
        require(priceFeed.decimals() == 8, "Unexpected price feed decimals");

        // Convert price to uint256 and get reward amount
        // assume $2000 for testing
        // Assuming the price feed has 8 decimals
        // Convert price to uint256 and get ethPriceUsd (the price of 1 ETH in USD)
        uint256 ethPriceUsd = uint256(price);

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

    // Owner can pause and unpause the contract
    function pause () external onlyOwner {
        _pause();
    }

    function unpause () external onlyOwner {
        _unpause();
    }

    function exists (uint256 tokenId) external view returns (bool) {
        return _exists(tokenId);
    }

    /// @notice Track each token transfer and increment the count
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId,
        uint256 batchSize
    ) internal override(ERC721, ERC721Enumerable) whenNotPaused {
        super._beforeTokenTransfer(from, to, tokenId, batchSize);

        // Increment the transfer count when the token is transferred (not minting or burning)
        // from === 0 is minting, to === 0 is burning
        if (from != address(0) && to != address(0)) {
            require(transferCount[tokenId] == 1, "Invalid transfer");
            require(merchantToken.hasValidMerchantToken(to), "Recipient must be a valid merchant");
            transferCount[tokenId] += 1;
        }
    }

    // Override the supportsInterface function to include ERC721Enumerable
    function supportsInterface (bytes4 interfaceId) public view override(ERC721, ERC721Enumerable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
