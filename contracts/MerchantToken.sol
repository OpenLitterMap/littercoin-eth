// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Import OpenZeppelin Contracts v4.9.2
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

/// @title MerchantToken Contract
/// @notice ERC721 token representing Merchant Tokens
contract MerchantToken is ERC721, Ownable {

    using Counters for Counters.Counter;

    // ID to give to each token
    Counters.Counter private _tokenCounter;

    // Mapping from owner address to token ID
    // Each address can only have one token
    mapping(address => uint256) private _ownedTokenId;

    // Mapping from token ID to expiration timestamp
    mapping(uint256 => uint256) private _expirationTimestamps;

    // Events
    event MerchantTokenMinted(address indexed to, uint256 tokenId, uint256 expiryTime);
    event MerchantTokenExpired(uint256 tokenId);
    event MerchantTokenRenewed(uint256 tokenId, uint256 newExpirationTimestamp);

    constructor() ERC721("LittercoinMerchantToken", "LXMT") {}

    /// @notice Mints a new Merchant Token to a specified address
    /// @notice - needs backend authorisation
    /// @param to The address to mint the token to
    function mint (address to, uint256 expirationTimestamp) external onlyOwner {
        require(to != address(0), "Cannot mint to zero address");
        require(expirationTimestamp > block.timestamp, "Expiration must be in the future.");
        require(balanceOf(to) == 0, "User already has a token");

        _tokenCounter.increment();
        uint256 tokenId = _tokenCounter.current();

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
    function addExpirationTime (uint256 tokenId, uint256 additionalTime) external onlyOwner {
        require(_exists(tokenId), "Token does not exist");
        require(additionalTime > 0, "Additional time must be greater than zero");

        _expirationTimestamps[tokenId] += additionalTime;

        emit MerchantTokenRenewed(tokenId, _expirationTimestamps[tokenId]);
    }

    /// @notice Invalidates a Merchant Token
    /// @param tokenId The ID of the token to invalidate
    function invalidateToken (uint256 tokenId) external onlyOwner {
        require(_exists(tokenId), "Token does not exist");
        require(!isExpired(tokenId), "Token already expired");

        // Set the expiration timestamp to one hour ago
        _expirationTimestamps[tokenId] = block.timestamp - 3600;

        emit MerchantTokenExpired(tokenId);
    }

    /// @notice Checks if a specific token has expired
    /// @param tokenId The ID of the token to check
    /// @return bool Returns true if the token is expired, otherwise false-
    function isExpired (uint256 tokenId) public view returns (bool) {
        require(_exists(tokenId), "Token does not exist");

        return block.timestamp > _expirationTimestamps[tokenId];
    }

    /// @notice Checks if an address holds at least one valid (non-expired) Merchant Token
    /// @param user The address to check
    /// @return bool True if the user holds a valid Merchant Token, false otherwise
    function hasValidMerchantToken (address user) public view returns (bool) {
        uint256 tokenId = _ownedTokenId[user];

        if (tokenId == 0 || isExpired(tokenId)) {
            return false;
        }

        return true;
    }

    function getExpirationTimestamp (uint256 tokenId) public view returns (uint256) {
        require(_exists(tokenId), "Token does not exist");

        return _expirationTimestamps[tokenId];
    }

    function getTokenIdByOwner (address owner) public view returns (uint256) {
        require(owner != address(0), "Invalid address");

        uint256 tokenId = _ownedTokenId[owner];

        require(tokenId != 0, "Owner does not have a token");

        return tokenId;
    }

    /// @notice Burns the Merchant Token of the caller
    function burn () external {
        uint256 tokenId = _ownedTokenId[msg.sender];

        require(tokenId != 0, "You do not own a token");

        _burn(tokenId);
    }

    /// @dev Overrides the _beforeTokenTransfer hook to prevent transfers
    function _beforeTokenTransfer (address from, address to, uint256 tokenId, uint256 batchSize) internal override {
        super._beforeTokenTransfer(from, to, tokenId, batchSize);

        // Prevent token transfers by reverting the transaction
        require(from == address(0) || to == address(0), "Transfers are disabled");

        if (from != address(0)) {
            // Token is being burned; clear the mapping
            _ownedTokenId[from] = 0;
        }
    }

    /// @dev Overrides the supportsInterface function to add ERC721
    function supportsInterface (bytes4 interfaceId) public view virtual override returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    // @notice Get the current token ID
    function getCurrentTokenId () external view returns (uint256) {
        return _tokenCounter.current();
    }
}
