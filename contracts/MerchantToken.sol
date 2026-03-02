// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/// @title MerchantToken Contract
/// @notice ERC721 token representing Merchant Tokens
contract MerchantToken is ERC721, Ownable, Pausable {

    // ID to give to each token
    uint256 private _nextTokenId;

    // Mapping from owner address to token ID
    // Each address can only have one token
    mapping(address => uint256) private _ownedTokenId;

    // Mapping from token ID to expiration timestamp
    mapping(uint256 => uint256) private _expirationTimestamps;

    // Merchant fee: $20 USD worth of ETH
    uint256 public constant MERCHANT_FEE_USD = 20;

    // Chainlink Price Feed
    AggregatorV3Interface internal priceFeed;

    // Tracks whether a merchant has paid the application fee
    mapping(address => bool) public feePaid;

    // Events
    event MerchantTokenMinted(address indexed to, uint256 tokenId, uint256 expiryTime);
    event MerchantTokenExpired(uint256 tokenId);
    event MerchantTokenRenewed(uint256 tokenId, uint256 newExpirationTimestamp);
    event MerchantFeeCollected(address indexed merchant, uint256 ethAmount, uint256 usdValue);
    event PriceFeedUpdated(address indexed oldFeed, address indexed newFeed);

    constructor(address initialOwner, address _priceFeed) ERC721("LittercoinMerchantToken", "LXMT") Ownable(initialOwner) {
        priceFeed = AggregatorV3Interface(_priceFeed);
    }

    /// @notice Merchants pay the $20 fee to become eligible for a merchant token
    function payMerchantFee() external payable whenNotPaused {
        require(!feePaid[msg.sender], "Fee already paid");
        require(balanceOf(msg.sender) == 0, "Already have a merchant token");

        // Get the latest ETH/USD price
        (, int256 price, , uint256 updatedAt, ) = priceFeed.latestRoundData();
        require(price > 0, "Invalid price from Chainlink");
        require(priceFeed.decimals() == 8, "Unexpected price feed decimals");
        require(block.timestamp - updatedAt < 3600, "Stale price feed");

        // Calculate minimum ETH required for $20
        // price has 8 decimals, msg.value is in wei (18 decimals)
        // $20 in ETH = (20 * 1e8 * 1e18) / price = (20 * 1e26) / price
        uint256 requiredEth = (MERCHANT_FEE_USD * 1e26) / uint256(price);
        require(msg.value >= requiredEth, "Insufficient ETH for merchant fee");

        feePaid[msg.sender] = true;

        // Send only the required fee to owner
        (bool success, ) = payable(owner()).call{value: requiredEth}("");
        require(success, "Fee transfer failed");

        // Refund any excess ETH to sender
        uint256 excess = msg.value - requiredEth;
        if (excess > 0) {
            (bool refundSuccess, ) = payable(msg.sender).call{value: excess}("");
            require(refundSuccess, "Refund failed");
        }

        emit MerchantFeeCollected(msg.sender, requiredEth, MERCHANT_FEE_USD);
    }

    /// @notice Mints a new Merchant Token to a specified address (owner approves after fee is paid)
    /// @param to The address to mint the token to
    function mint (address to, uint256 expirationTimestamp) external onlyOwner whenNotPaused {
        require(to != address(0), "Cannot mint to zero address");
        require(expirationTimestamp > block.timestamp, "Expiration must be in the future.");
        require(balanceOf(to) == 0, "User already has a token");
        require(feePaid[to], "Merchant fee not paid");

        // Clear the fee paid flag
        feePaid[to] = false;

        ++_nextTokenId;
        uint256 tokenId = _nextTokenId;

        // Store the expiration timestamp before minting
        _expirationTimestamps[tokenId] = expirationTimestamp;

        // Mint the MerchantToken
        _safeMint(to, tokenId);

        // Assign the token ID to the owner
        _ownedTokenId[to] = tokenId;

        emit MerchantTokenMinted(to, tokenId, expirationTimestamp);
    }

    /// @notice Adds additional expiration time to an existing Merchant Token
    /// @param tokenId The ID of the token to renew
    /// @param additionalTime The additional time to add to the current expiration
    function addExpirationTime (uint256 tokenId, uint256 additionalTime) external onlyOwner whenNotPaused {
        require(_ownerOf(tokenId) != address(0), "Token does not exist");
        require(additionalTime > 0, "Additional time must be greater than zero");

        _expirationTimestamps[tokenId] += additionalTime;

        emit MerchantTokenRenewed(tokenId, _expirationTimestamps[tokenId]);
    }

    /// @notice Invalidates a Merchant Token
    /// @param tokenId The ID of the token to invalidate
    function invalidateToken (uint256 tokenId) external onlyOwner whenNotPaused {
        require(_ownerOf(tokenId) != address(0), "Token does not exist");
        require(!isExpired(tokenId), "Token already expired");

        // Set the expiration timestamp to one hour ago
        _expirationTimestamps[tokenId] = block.timestamp - 3600;

        emit MerchantTokenExpired(tokenId);
    }

    /// @notice Checks if a specific token has expired
    /// @param tokenId The ID of the token to check
    /// @return bool Returns true if the token is expired, otherwise false
    function isExpired (uint256 tokenId) public view returns (bool) {
        require(_ownerOf(tokenId) != address(0), "Token does not exist");

        return block.timestamp > _expirationTimestamps[tokenId];
    }

    /// @notice Checks if an address holds at least one valid (non-expired) Merchant Token
    /// @param user The address to check
    /// @return bool True if the user holds a valid Merchant Token, false otherwise
    function hasValidMerchantToken (address user) public view returns (bool) {
        uint256 tokenId = _ownedTokenId[user];

        if (tokenId == 0 || _ownerOf(tokenId) == address(0)) {
            return false;
        }

        if (isExpired(tokenId)) {
            return false;
        }

        return true;
    }

    /// @notice Checks if an address holds a Merchant Token (regardless of expiry)
    /// @param user The address to check
    /// @return bool True if the user holds a Merchant Token, false otherwise
    function hasMerchantToken (address user) public view returns (bool) {
        uint256 tokenId = _ownedTokenId[user];
        if (tokenId == 0) return false;
        return _ownerOf(tokenId) != address(0);
    }

    function getExpirationTimestamp (uint256 tokenId) public view returns (uint256) {
        require(_ownerOf(tokenId) != address(0), "Token does not exist");

        return _expirationTimestamps[tokenId];
    }

    function getTokenIdByOwner (address _owner) public view returns (uint256) {
        require(_owner != address(0), "Invalid address");

        uint256 tokenId = _ownedTokenId[_owner];

        require(tokenId != 0, "Owner does not have a token");

        return tokenId;
    }

    /// @notice Burns the Merchant Token of the caller
    function burn () external whenNotPaused {
        uint256 tokenId = _ownedTokenId[msg.sender];

        require(tokenId != 0, "You do not own a token");

        _burn(tokenId);
    }

    /// @notice Update the Chainlink price feed address
    function setPriceFeed (address _priceFeed) external onlyOwner {
        require(_priceFeed != address(0), "Invalid address");
        address oldFeed = address(priceFeed);
        priceFeed = AggregatorV3Interface(_priceFeed);
        emit PriceFeedUpdated(oldFeed, _priceFeed);
    }

    function pause () external onlyOwner {
        _pause();
    }

    function unpause () external onlyOwner {
        _unpause();
    }

    /// @dev Soulbound: approvals are disabled since transfers are not allowed
    function approve(address, uint256) public pure override {
        revert("Soulbound: approvals disabled");
    }

    /// @dev Soulbound: approvals are disabled since transfers are not allowed
    function setApprovalForAll(address, bool) public pure override {
        revert("Soulbound: approvals disabled");
    }

    /// @dev Overrides the _update hook to prevent transfers (soulbound)
    function _update(address to, uint256 tokenId, address auth) internal override returns (address) {
        address from = _ownerOf(tokenId);

        // Only allow minting (from == 0) and burning (to == 0)
        if (from != address(0) && to != address(0)) {
            revert("Transfers are disabled");
        }

        if (from != address(0)) {
            // Token is being burned; clear the mapping
            _ownedTokenId[from] = 0;
        }

        return super._update(to, tokenId, auth);
    }

    /// @dev Overrides the supportsInterface function to add ERC721
    function supportsInterface (bytes4 interfaceId) public view virtual override returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    // @notice Get the current token ID
    function getCurrentTokenId () external view returns (uint256) {
        return _nextTokenId;
    }
}
