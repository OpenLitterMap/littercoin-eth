# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Test Commands

```bash
npx hardhat compile          # Compile all Solidity contracts
npx hardhat test             # Run all tests
npx hardhat test --grep "should mint Littercoin"  # Run a single test by name
```

Uses Hardhat with hardhat-toolbox. Solidity version 0.8.27. Tests are in JavaScript (Mocha/Chai) using ethers.js v6.

## Architecture

Littercoin is an exchangeless, non-tradable climate currency. Users earn Littercoin by contributing data to OpenLitterMap, then spend it exclusively with approved zero-waste merchants. The system has a 3-transaction lifecycle per token: mint → transfer to merchant → burn for ETH.

### Contracts

**Littercoin.sol** — Main ERC721 (NFT) contract. Each Littercoin is a unique NFT with a constrained lifecycle:
- **Mint**: Users mint via EIP-712 signed messages from the backend (owner signs, user submits). Merchants cannot mint.
- **Transfer**: Users can transfer a token exactly once, and only to a valid merchant. `tokenTransferred[tokenId]` tracks this.
- **Burn**: Merchants call `burnLittercoin(tokenIds)` to redeem proportional ETH from the contract pool (`contractBalance * numTokens / totalSupply`).
- **receive()**: Accepts ETH donations and mints OLMRewardTokens proportional to USD value (via Chainlink price feed).

All transfer rules are enforced in `_beforeTokenTransfer`. Inherits ERC721Enumerable, Ownable, ReentrancyGuard, Pausable, EIP712.

**MerchantToken.sol** — Soulbound ERC721 (transfers disabled via `_beforeTokenTransfer`). Owner-minted with an expiration timestamp. One token per address. Used as a gatekeeper: `hasValidMerchantToken(address)` checks existence + expiry.

**OLMRewardToken.sol** — Simple ERC20 minted by the Littercoin contract when ETH is received. Owned by the Littercoin contract.

**MockV3Aggregator.sol** — Test mock for Chainlink's AggregatorV3Interface (ETH/USD price feed).

### Deployment Topology

The Littercoin constructor deploys both OLMRewardToken and MerchantToken:
- `rewardToken.transferOwnership(address(this))` — Littercoin contract owns it (needs to call `mint`)
- `merchantToken.transferOwnership(msg.sender)` — deployer/admin owns it (manages merchant approvals)

### Key Dependencies

- OpenZeppelin Contracts v4.9.2 (uses `Counters`, `ReentrancyGuard`, `Pausable`, `EIP712`, `ECDSA`)
- Chainlink contracts for price feed interface
