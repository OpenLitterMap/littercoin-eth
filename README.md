# Littercoin

**An exchangeless, non-tradable climate currency on Ethereum.**

> **Status: In development — not yet audited.**

## Overview

Littercoin tokenises the production of geographic information. Users earn Littercoin by contributing litter data to [OpenLitterMap](https://openlittermap.com) — upload 100 photos and receive 1 Littercoin. Each Littercoin is an ERC-721 NFT with a constrained 3-transaction lifecycle: **mint, transfer, burn**.

Littercoin gets its value from an ETH pool held in the smart contract. If the pool holds $20,000 worth of ETH and 100 Littercoin are in circulation, each is worth $200. Littercoin can only be spent with pre-approved zero-waste merchants who do not use plastic.

There is no ICO, no pre-mine, and no exchanges.

## Token Lifecycle

Each Littercoin NFT has exactly 3 transactions in its lifetime:

```
  ┌──────────┐         ┌──────────┐         ┌──────────────────┐
  │  1. MINT │         │2.TRANSFER│         │     3. BURN      │
  │          │         │          │         │                  │
  │ Backend  │         │ User     │         │ Merchant sends   │
  │ signs    ├────────►│ sends to ├────────►│ to contract,     │
  │ EIP-712, │         │ merchant │         │ receives ETH     │
  │ user     │         │ (once)   │         │                  │
  │ claims   │         │          │         │ ETH = pool *     │
  │ (max 10) │         │          │         │ tokens / supply  │
  └──────────┘         └──────────┘         └──────────────────┘
```

Any transfer that violates these rules is rejected by the contract.

## Architecture

### Contract Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                     Littercoin Contract                         │
│                     (ERC-721 NFT + ETH Pool)                   │
│                                                                 │
│  ┌──────────────┐  ┌──────────────────┐  ┌──────────────────┐  │
│  │  Mint Logic  │  │  Transfer Rules  │  │  Burn + Redeem   │  │
│  │  (EIP-712)   │  │  (User→Merchant) │  │  (ETH payout)    │  │
│  └──────────────┘  └──────────────────┘  └──────────────────┘  │
│                                                                 │
│  Deploys & Owns:             Deploys (Admin Owns):             │
│  ┌──────────────────┐        ┌──────────────────┐              │
│  │ OLMRewardToken   │        │ MerchantToken    │              │
│  │ (ERC-20)         │        │ (Soulbound NFT)  │              │
│  └──────────────────┘        └──────────────────┘              │
└─────────────────────────────────────────────────────────────────┘
```

### Contracts

| Contract | Type | Purpose |
|---|---|---|
| **Littercoin** | ERC-721 (Enumerable) | Main token. Mint via EIP-712, transfer to merchants, burn for ETH. Holds the ETH pool and deploys child contracts. |
| **MerchantToken** | ERC-721 (Soulbound) | Non-transferable. Minted by admin with an expiration timestamp. One per address. Gates who can receive and redeem Littercoin. |
| **OLMRewardToken** | ERC-20 | Minted when ETH is sent to the Littercoin contract. 1 OLMRT per $1 USD of ETH donated (via Chainlink price feed). |
| **MockV3Aggregator** | — | Test mock for Chainlink's AggregatorV3Interface (ETH/USD). |

### ETH Pool and Value

```
                    ┌──────────────────────┐
                    │  Littercoin Contract  │
                    │     (ETH Pool)       │
                    │                      │
  Supporters ──────►│  ETH Balance: $X     │◄────── Value grows
  send ETH          │                      │        as more ETH
                    │  Total Supply: N     │        is donated
  Get back:         │  tokens              │
  OLMRewardTokens   │                      │  Merchants burn:
  ($1 = 1 OLMRT)    │  Value per token:    │  Get ETH out
                    │  $X / N              │──────► ETH payout
                    │                      │
                    └──────────────────────┘
```

### Merchant Token Lifecycle

```
  ┌──────────┐     ┌───────────────┐     ┌─────────────────┐
  │  Admin   │     │ MerchantToken │     │    Merchant     │
  │ (Owner)  │     │  (Soulbound)  │     │                 │
  │          │     │               │     │ - Can receive   │
  │ Approves ├────►│ Mint with     ├────►│   Littercoin    │
  │ merchant │     │ expiry date   │     │ - Can burn for  │
  │          │     │               │     │   ETH           │
  │ Can also │     │ Non-          │     │ - Cannot mint   │
  │ renew or │     │ transferable  │     │   Littercoin    │
  │ invalidate│    │               │     │ - Cannot trade  │
  └──────────┘     └───────────────┘     └─────────────────┘

  States:
  ┌────────┐  mint   ┌────────┐  time passes  ┌─────────┐
  │  None  ├────────►│ Active ├──────────────►│ Expired │
  └────────┘         └───┬────┘               └─────────┘
                         │ invalidate              │
                         ▼                         │ addExpirationTime
                    ┌─────────┐                    │
                    │ Expired │◄───────────────────┘
                    └─────────┘
```

### Roles

| Role | Can Do | Cannot Do |
|---|---|---|
| **User** | Mint Littercoin (with backend signature), transfer to merchants, send ETH to contract | Burn Littercoin, mint if holding a Merchant Token |
| **Merchant** | Receive Littercoin from users, burn Littercoin for proportional ETH | Mint Littercoin, transfer Littercoin to others |
| **Admin** | Mint/invalidate/renew Merchant Tokens, sign EIP-712 mint authorizations, pause/unpause contracts | — |

## Development

### Prerequisites

- Node.js
- npm

### Setup

```bash
npm install
```

### Build and Test

```bash
npx hardhat compile          # Compile contracts
npx hardhat test             # Run all tests
npx hardhat test --grep "should mint Littercoin"  # Run a single test
```

### Tech Stack

- **Solidity** 0.8.27
- **Hardhat** with hardhat-toolbox
- **OpenZeppelin** Contracts v4.9.2
- **Chainlink** price feed (ETH/USD)
- **Tests**: JavaScript (Mocha/Chai) with ethers.js v6

## License

MIT
