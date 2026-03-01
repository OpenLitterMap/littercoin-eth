// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// Import OpenZeppelin Contracts v5
import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { ERC721Enumerable } from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";

// Import Dependencies
import { MerchantToken } from "./MerchantToken.sol";
import { OLMThankYouToken } from "./OLMThankYouToken.sol";

import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

contract Littercoin is ERC721, ERC721Enumerable, Ownable, ReentrancyGuard, Pausable, EIP712 {

    // ID of the next Littercoin to be minted
    uint256 private _nextTokenId;

    // Used nonces for preventing replay attacks
    mapping(uint256 => bool) public usedNonces;

    // Mapping to check if each Littercoin has been transferred from a User to a Merchant
    mapping(uint256 => bool) public tokenTransferred;

    // Define a limit for the number of Littercoin tokens that can be minted at once
    uint256 public constant MAX_MINT_AMOUNT = 10;

    // Burn tax: 4.20% (420 basis points out of 10000)
    uint256 public constant BURN_TAX_BPS = 420;
    uint256 public constant BPS_DENOMINATOR = 10000;

    // OLM Thank You Token
    OLMThankYouToken public rewardToken;

    // Merchant Token
    MerchantToken public merchantToken;

    // Chainlink Price Feed
    AggregatorV3Interface internal priceFeed;

    bytes32 private constant MINT_TYPEHASH = keccak256("Mint(address user,uint256 amount,uint256 nonce,uint256 expiry)");

    /// @notice Contract constructor
    constructor (address _priceFeed)
        ERC721("Littercoin", "LITTERX")
        Ownable(msg.sender)
        EIP712("Littercoin", "1")
    {
        // Deploy the Thank You Token with this contract as owner
        rewardToken = new OLMThankYouToken(address(this));

        // Deploy the Merchant Token with deployer as owner and price feed
        merchantToken = new MerchantToken(msg.sender, _priceFeed);

        // Set up Chainlink Price Feed (ETH/USD on mainnet)
        priceFeed = AggregatorV3Interface(_priceFeed);
    }

    /// @notice Event emitted when a user mints Littercoin
    event Mint(address indexed user, uint256 amount);

    /// @notice Event emitted when a valid Merchant Token Holder burns Littercoin for ETH
    event BurnLittercoin (address indexed user, uint256 tokensToBurn, uint256 ethAmount);

    /// @notice Event emitted when a user is rewarded OLM Thank You Tokens
    event Reward (address indexed user, uint256 rewardAmount);

    /// @notice Event emitted when burn tax is collected
    event BurnTaxCollected(address indexed owner, uint256 taxAmount);

    /// @notice Getter function for rewardToken address
    function getRewardTokenAddress() external view returns (address) {
        return address(rewardToken);
    }

    /// @notice Getter function for merchantToken address
    function getMerchantTokenAddress() external view returns (address) {
        return address(merchantToken);
    }

    /// @notice
    function _hashMint (address user, uint256 amount, uint256 nonce, uint256 expiry) internal view returns (bytes32) {
        return _hashTypedDataV4(
            keccak256(
                abi.encode(
                    MINT_TYPEHASH,
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
        require(amount > 0 && amount <= MAX_MINT_AMOUNT, "Amount must be between 1 and 10");
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
            ++_nextTokenId;
            uint256 tokenId = _nextTokenId;

            // Mint tokens to the user
            _safeMint(msg.sender, tokenId);
        }

        emit Mint(msg.sender, amount);
    }

    /// @notice Burn multiple Littercoin NFTs and transfer the average ETH per NFT to the merchant
    /// @param tokenIds The IDs of the Littercoin NFTs to redeem
    function burnLittercoin (uint256[] calldata tokenIds) external nonReentrant whenNotPaused {
        require(merchantToken.hasMerchantToken(msg.sender), "Must hold a Merchant Token.");

        // Check for Littercoin to burn
        uint256 numTokens = tokenIds.length;
        require(numTokens > 0, "No tokens provided.");

        uint256 currentSupply = totalSupply();
        require(currentSupply > 0, "No tokens in circulation.");

        // Ensure there is more than 0 ETH in the contract
        uint256 contractBalance = address(this).balance;
        require(contractBalance > 0, "Not enough ETH in contract.");

        // Validate all and process each token
        for (uint256 i = 0; i < numTokens; i++) {
            uint256 tokenId = tokenIds[i];
            require(ownerOf(tokenId) == msg.sender, "Caller must own all tokens being redeemed.");
            _burn(tokenId);
        }

        // Calculate the total ETH to redeem
        uint256 totalEthToTransfer = (contractBalance * numTokens) / currentSupply;
        require(totalEthToTransfer > 0, "ETH amount too small to redeem");

        // Calculate the 4.20% burn tax
        uint256 taxAmount = (totalEthToTransfer * BURN_TAX_BPS) / BPS_DENOMINATOR;
        uint256 merchantAmount = totalEthToTransfer - taxAmount;

        // Transfer tax to owner
        if (taxAmount > 0) {
            (bool taxSuccess, ) = payable(owner()).call{value: taxAmount}("");
            require(taxSuccess, "Tax transfer failed");
            emit BurnTaxCollected(owner(), taxAmount);
        }

        // Transfer remaining ETH to merchant
        (bool success, ) = payable(msg.sender).call{value: merchantAmount}("");
        require(success, "Transfer failed");

        emit BurnLittercoin(msg.sender, numTokens, merchantAmount);
    }

    /// @notice Accepts ETH and rewards OLMThankYouTokens based on the amount
    receive () external payable nonReentrant whenNotPaused {
        uint256 ethAmount = msg.value;

        // Get the latest ETH/USD price
        (, int256 price, , uint256 updatedAt, ) = priceFeed.latestRoundData();
        require(price > 0, "Invalid price from Chainlink");
        require(priceFeed.decimals() == 8, "Unexpected price feed decimals");
        require(block.timestamp - updatedAt < 3600, "Stale price feed");

        // Convert price to uint256 and get reward amount
        // Assuming the price feed has 8 decimals
        // Convert price to uint256 and get ethPriceUsd (the price of 1 ETH in USD)
        uint256 ethPriceUsd = uint256(price);

        // Calculate the number of reward tokens to mint
        // ethPriceUsd has 8 decimals, so divide by 10^8 to get the actual USD value
        // ethAmount is in wei (10^18), so divide by 10^18 to convert to ETH
        // rewardAmount = ethAmount (in USD) * (1 OLMThankYouToken / 1 USD)
        uint256 rewardAmount = (ethAmount * ethPriceUsd) / 1e8;

        // Mint OLM Thank You Tokens to the sender
        rewardToken.mint(msg.sender, rewardAmount);

        emit Reward(msg.sender, rewardAmount);
    }

    // @notice Get the current token ID
    function getCurrentTokenId () external view returns (uint256) {
        return _nextTokenId;
    }

    function pause () external onlyOwner {
        _pause();
    }

    function unpause () external onlyOwner {
        _unpause();
    }

    function exists (uint256 tokenId) external view returns (bool) {
        return _ownerOf(tokenId) != address(0);
    }

    /// @notice Track each token transfer and enforce lifecycle rules
    function _update(address to, uint256 tokenId, address auth)
        internal
        override(ERC721, ERC721Enumerable)
        returns (address)
    {
        // Enforce pause on all token operations
        _requireNotPaused();

        address from = _ownerOf(tokenId);

        // from === 0 is minting, to === 0 is burning
        if (from == address(0)) {
            // Minting
            // Prevent merchants from minting tokens
            require(!merchantToken.hasValidMerchantToken(to), "Merchants cannot mint Littercoin");
        } else if (to == address(0)) {
            // Burning
            // Only allow merchants to burn tokens
            require(merchantToken.hasMerchantToken(from), "Only merchants can burn tokens");
        } else {
            // Transferring
            // Ensure the token hasn't been transferred before
            require(!tokenTransferred[tokenId], "Token has already been transferred");

            // Ensure sender is not a merchant
            require(!merchantToken.hasValidMerchantToken(from), "Merchants cannot transfer tokens");

            // Ensure recipient is a valid merchant
            require(merchantToken.hasValidMerchantToken(to), "Recipient must be a valid merchant");

            // Mark the token as transferred
            tokenTransferred[tokenId] = true;
        }

        return super._update(to, tokenId, auth);
    }

    // Required override for ERC721Enumerable
    function _increaseBalance(address account, uint128 value)
        internal
        override(ERC721, ERC721Enumerable)
    {
        super._increaseBalance(account, value);
    }

    // Override the supportsInterface function to include ERC721Enumerable
    function supportsInterface (bytes4 interfaceId) public view override(ERC721, ERC721Enumerable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
