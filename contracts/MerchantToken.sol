// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Import OpenZeppelin Contracts v4.9.2
import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
// import { ERC721Enumerable } from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

/// @title MerchantToken Contract
/// @notice ERC721 token representing Merchant Tokens
contract MerchantToken is ERC721, Ownable {

    // ID to give to each token
    uint256 public _tokenCounter;

    // Mapping to determine whether a user has a valid Merchant Token
    mapping(address => bool) private _hasValidToken;

    // Mapping from token ID to expiration timestamp
    mapping(uint256 => uint256) private _expirationTimestamps;

    // Events
    event MerchantTokenExpired(uint256 tokenId);
    event MerchantTokenRenewed(uint256 tokenId, uint256 newExpirationTimestamp);
    event MerchantTokenMinted(address indexed to, uint256 tokenId, uint256 expiryTime);
    event MerchantTokenTransferred(address indexed from, address indexed to, uint256 tokenId);

    constructor() ERC721("LittercoinMerchantToken", "LXMT") {
        _tokenCounter = 1;
    }

    /// @notice Mints a new Merchant Token to a specified address
    /// @notice - needs backend authorisation
    /// @param to The address to mint the token to
    function mint (address to, uint256 expirationTimestamp) external onlyOwner {
        require(to != address(0), "Cannot mint to zero address");
        require(expirationTimestamp > block.timestamp, "Expiration must be in the future");

        uint256 tokenId = _tokenCounter;
        _tokenCounter += 1;

        // Store the expiration timestamp before minting
        _expirationTimestamps[tokenId] = expirationTimestamp;

        // Mint the MerchantToken
        _safeMint(to, tokenId);

        // Update valid token mapping
        _hasValidToken[to] = true;

        emit MerchantTokenMinted(to, tokenId, expirationTimestamp);
    }

    /// @notice Renews the expiration timestamp of a Merchant Token
    /// @param tokenId The ID of the token to renew
    /// @param newExpirationTimestamp The new expiration timestamp
    function renewToken (uint256 tokenId, uint256 newExpirationTimestamp) external onlyOwner {
        require(_exists(tokenId), "Token does not exist");
        require(newExpirationTimestamp > block.timestamp, "Expiration must be in the future");
        require(newExpirationTimestamp > _expirationTimestamps[tokenId], "New expiration must be later than current");

        _expirationTimestamps[tokenId] = newExpirationTimestamp;

        address owner = ownerOf(tokenId);
        _hasValidToken[owner] = true;

        emit MerchantTokenRenewed(tokenId, newExpirationTimestamp);
    }

    /// @notice Checks if a specific token has expired
    /// @param tokenId The ID of the token to check
    /// @return bool Returns true if the token is expired, otherwise false
    function isExpired (uint256 tokenId) public view returns (bool) {
        require(_exists(tokenId), "Token does not exist");

        return block.timestamp > _expirationTimestamps[tokenId];
    }

    /// @notice Checks if an address holds at least one valid (non-expired) Merchant Token
    /// @param user The address to check
    /// @return bool True if the user holds a valid Merchant Token, false otherwise
    function hasValidMerchantToken (address user) public view returns (bool) {
        return _hasValidToken[user];
    }

    /// @dev Internal function to update the _hasValidToken mapping for a user
    ///      This function loops over the user's tokens only when necessary (on transfers and expirations)
    /// @param user The address to update
    function _updateHasValidToken (address user) internal {
        uint256[] storage tokens = _ownedTokens[user];
        bool validTokenFound = false;

        for (uint256 i = 0; i < tokens.length; i++) {
            if (!isExpired(tokens[i])) {
                validTokenFound = true;
                break;
            }
        }

        _hasValidToken[user] = validTokenFound;
    }

    /// @dev Overrides the _beforeTokenTransfer hook to update token ownership mappings
    ///      and the _hasValidToken mapping efficiently
    function _beforeTokenTransfer (address from, address to, uint256 tokenId, uint256 batchSize) internal override {
        super._beforeTokenTransfer(from, to, tokenId, batchSize);

        if (from == address(0)) {
            // Minting
            _addTokenToOwnerEnumeration(to, tokenId);
            _hasValidToken[to] = true; // Token is valid upon minting
        } else if (to == address(0)) {
            // Burning
            _removeTokenFromOwnerEnumeration(from, tokenId);
            _updateHasValidToken(from);
        } else {
            // Transferring
            _removeTokenFromOwnerEnumeration(from, tokenId);
            _addTokenToOwnerEnumeration(to, tokenId);
            _updateHasValidToken(from);

            // Update recipient's valid token status
            if (!isExpired(tokenId)) {
                _hasValidToken[to] = true;
            }
        }

        emit MerchantTokenTransferred(from, to, tokenId);
    }

    // ================================
    //       Owner Enumeration Logic
    // ================================

    // Mapping from owner to list of owned token IDs
    mapping(address => uint256[]) private _ownedTokens;

    // Mapping from token ID to index in the owner's tokens list
    mapping(uint256 => uint256) private _ownedTokensIndex;

    /// @dev Adds a token to the enumeration mapping of the owner
    /// @param to The address of the owner
    /// @param tokenId The token ID to add
    function _addTokenToOwnerEnumeration(address to, uint256 tokenId) internal {
        _ownedTokensIndex[tokenId] = _ownedTokens[to].length;
        _ownedTokens[to].push(tokenId);
    }

    /// @dev Removes a token from the enumeration mapping of the owner
    /// @param from The address of the previous owner
    /// @param tokenId The token ID to remove
    function _removeTokenFromOwnerEnumeration(address from, uint256 tokenId) internal {
        uint256 lastIndex = _ownedTokens[from].length - 1;
        uint256 tokenIndex = _ownedTokensIndex[tokenId];

        if (tokenIndex != lastIndex) {
            uint256 lastTokenId = _ownedTokens[from][lastIndex];

            _ownedTokens[from][tokenIndex] = lastTokenId;
            _ownedTokensIndex[lastTokenId] = tokenIndex;
        }

        _ownedTokens[from].pop();
        delete _ownedTokensIndex[tokenId];
    }

    /// @notice Gets the list of token IDs owned by an address
    /// @param owner The address to query
    /// @return uint256[] List of token IDs
    function tokensOfOwner(address owner) external view returns (uint256[] memory) {
        return _ownedTokens[owner];
    }

    // ================================
    //          Expiration Logic
    // ================================

    /// @notice Expires a token manually
    /// @param tokenId The ID of the token to expire
    function expireToken(uint256 tokenId) external onlyOwner {
        require(_exists(tokenId), "Token does not exist");
        require(!isExpired(tokenId), "Token already expired");

        _expirationTimestamps[tokenId] = block.timestamp;

        address owner = ownerOf(tokenId);
        _updateHasValidToken(owner);

        emit MerchantTokenExpired(tokenId);
    }

    // ================================
    //          ERC165 Support
    // ================================

    /// @dev See {IERC165-supportsInterface}
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
