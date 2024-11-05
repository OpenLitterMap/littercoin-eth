// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Import OpenZeppelin Contracts v4.9.2
import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { ERC721Enumerable } from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

/// @title MerchantToken Contract
/// @notice ERC721 token representing Merchant Tokens
contract MerchantToken is ERC721, ERC721Enumerable, Ownable {
    uint256 public tokenCounter;
    uint256 public constant DEFAULT_EXPIRY_PERIOD = 365 days;

    // Mapping to store expiration timestamp for each token
    mapping(uint256 => uint256) private _tokenExpiry;

    /// @notice Event emitted when a Merchant Token is minted
    event MerchantTokenMinted(address indexed to, uint256 tokenId, uint256 expiryTime);

    constructor() ERC721("MerchantToken", "LCMT") {
        tokenCounter = 1;
    }

    /// @notice Mints a new Merchant Token to a specified address
    /// @notice - needs backend authorisation
    /// @param to The address to mint the token to
    function mint (address to) external onlyOwner {
        uint256 tokenId = tokenCounter;
        tokenCounter += 1;

        // Track token expiry
        uint256 expiryTime = block.timestamp + DEFAULT_EXPIRY_PERIOD;
        _tokenExpiry[tokenId] = expiryTime;

        // Mint the MerchantToken
        _safeMint(to, tokenId);

        // Broadcast event
        emit MerchantTokenMinted(to, tokenId, expiryTime);
    }

    /// @notice Checks if a specific token has expired
    /// @param tokenId The ID of the token to check
    /// @return bool Returns true if the token is expired, otherwise false
    function isExpired (uint256 tokenId) public view returns (bool) {
        require(_exists(tokenId), "Token does not exist");

        return block.timestamp > _tokenExpiry[tokenId];
    }

    /// @notice Checks if a user holds a valid (non-expired) Merchant Token
    /// @param user The address of the user
    /// @return bool Returns true if the user holds at least one valid Merchant Token, otherwise false
    function hasValidMerchantToken (address user) public view returns (bool) {
        uint256 balance = balanceOf(user);

        if (balance == 0) {
            return false;
        }

        for (uint256 i = 0; i < balance; i++) {
            uint256 tokenId = tokenOfOwnerByIndex(user, i);

            if (!isExpired(tokenId)) {
                // User has at least one valid Merchant Token
                return true;
            }
        }

        // No valid Merchant Tokens found
        return false;
    }

    /// @notice Gets the expiry timestamp of a specific token
    /// @param tokenId The ID of the token
    /// @return uint256 The expiry timestamp of the token
    function getExpiry (uint256 tokenId) public view returns (uint256) {
        require(_exists(tokenId), "Token does not exist");

        return _tokenExpiry[tokenId];
    }

    /**
     * These 2 override functions are necessary because your contract inherits from multiple OpenZeppelin contracts
     * (ERC721, ERC721Enumerable, and Ownable). Solidity requires explicit handling of functions with the same name
     * in multiple inherited contracts to resolve any ambiguity.
     */

    // Override required functions from parent contracts
    function supportsInterface (bytes4 interfaceId) public view override (ERC721, ERC721Enumerable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId,
        uint256 batchSize
    ) internal override (ERC721, ERC721Enumerable) {
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
    }
}
