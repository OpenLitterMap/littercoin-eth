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
- **Mint**: Users mint via EIP-712 signed messages from the backend (owner signs, user submits). Per-user nonces prevent replay. Merchants cannot mint.
- **Transfer**: Users can transfer a token exactly once, and only to a valid merchant. `tokenTransferred[tokenId]` tracks this.
- **Burn**: Merchants call `burnLittercoin(tokenIds)` to redeem proportional ETH from the redeemable pool (excludes accumulated tax). A 4.20% burn tax is tried first as a direct transfer to owner; on failure it accumulates for pull-based withdrawal via `withdrawTax()`. Max 50 tokens per burn.
- **donate()**: Accepts ETH donations and mints OLMThankYouTokens proportional to USD value (via Chainlink price feed). Has `nonReentrant` and `whenNotPaused`.
- **receive()**: Accepts plain ETH into the pool silently (no reward tokens). Donors who want OLMTY should call `donate()`.

All transfer rules are enforced in the `_update` hook (OZ v5). Inherits ERC721Enumerable, Ownable, ReentrancyGuard, Pausable, EIP712.

**MerchantToken.sol** — Soulbound ERC721 (transfers and approvals disabled via `_update` and `approve`/`setApprovalForAll` overrides). Owner-minted with an expiration timestamp after merchant pays a $20 USD fee (with overpayment refund). One token per address. Used as a gatekeeper: `hasValidMerchantToken(address)` checks existence + expiry.

**OLMThankYouToken.sol** — Simple ERC20 minted by the Littercoin contract when ETH is donated via `donate()`. Owned by the Littercoin contract.

**MockV3Aggregator.sol** — Test mock for Chainlink's AggregatorV3Interface (ETH/USD price feed).

### Deployment Topology

The Littercoin constructor deploys both OLMThankYouToken and MerchantToken:
- `OLMThankYouToken(address(this))` — Littercoin contract is set as owner (needs to call `mint`)
- `MerchantToken(msg.sender, _priceFeed)` — deployer/admin is set as owner (manages merchant approvals)

### Key Dependencies

- OpenZeppelin Contracts v5 (uses `ReentrancyGuard`, `Pausable`, `EIP712`, `ECDSA`, `Ownable`)
- Chainlink contracts for price feed interface (`AggregatorV3Interface`)
