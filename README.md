# Littercoin

**An exchangeless, non-tradable climate currency on Ethereum.**

> **Status: In development — not yet audited.**

## What is Littercoin?

Littercoin turns litter cleanup into crypto.

Users earn Littercoin by uploading litter data to
[OpenLitterMap](https://openlittermap.com).
100 photos = 1 Littercoin.
Each Littercoin is an NFT backed by real ETH.

Littercoin can only be spent with approved
zero-waste merchants — businesses that don't
use plastic. Merchants burn Littercoin to
withdraw ETH from the pool.

There is no ICO, no pre-mine, and no exchanges.

## How It Works

```
  DONORS             USERS              MERCHANTS
    |                  |                    |
    | Send ETH         | Pick up litter,   |
    | to contract      | upload to OLM,    |
    v                  | earn Littercoin    |
                       v                    |
  +--------------------+--------------------+
  |                                         |
  |         Littercoin Contract             |
  |         (ETH Pool)                      |
  |                                         |
  |   Pool Balance ÷ Supply                 |
  |   = Value Per Token                     |
  |                                         |
  +--------------------+--------------------+
                       |                    |
                       | Transfer           | Burn
                       | Littercoin         | Littercoin
                       | to merchant        | for ETH
                       v                    v
                    MERCHANT           ETH PAYOUT
                    WALLET          95.8% merchant
                                     4.2% platform
```

More donations = higher token value =
stronger incentive to pick up litter.

## Token Lifecycle

Each Littercoin has exactly 3 transactions:

```
  1. MINT            2. TRANSFER         3. BURN
  --------           -----------         ------

  Backend signs      User sends          Merchant burns
  EIP-712 msg        Littercoin          token, gets
  User claims        to a merchant       proportional
  on-chain           (one time only)     ETH from pool
  (max 10)
```

Any transfer that violates these rules
is rejected by the contract.

## Revenue Model

The platform earns passive income
through two mechanisms:

```
  BURN TAX (4.20%)
  ----------------
  Every time a merchant burns
  Littercoin for ETH:

  Total ETH payout
    |
    +-- 95.80% --> Merchant
    +--  4.20% --> Platform owner


  MERCHANT FEE ($20)
  ------------------
  Zero-waste merchants pay $20
  in ETH to apply for approval:

  Merchant pays fee
    |
    +-- $20 ETH --> Platform owner
    |
  Admin approves
    |
    +-- Merchant Token minted
```

## Contracts

```
  Littercoin (ERC-721)
  Main contract. Holds ETH pool.
  Deploys child contracts.
  |
  +-- OLMThankYouToken (ERC-20)
  |   Minted to ETH donors.
  |   $1 donated = 1 OLMTY.
  |   Owned by Littercoin contract.
  |
  +-- MerchantToken (ERC-721)
      Soulbound. Non-transferable.
      One per address. Has expiry.
      $20 fee to apply.
      Owned by admin.
```

| Contract | Type | Purpose |
|---|---|---|
| **Littercoin** | ERC-721 Enumerable | Main token. Mint via EIP-712, transfer to merchants, burn for ETH. Holds the ETH pool. 4.20% burn tax. |
| **MerchantToken** | ERC-721 Soulbound | Non-transferable. $20 fee + admin approval. Expiration timestamp. One per address. |
| **OLMThankYouToken** | ERC-20 | Minted when ETH is donated. 1 OLMTY per $1 USD (via Chainlink). |
| **MockV3Aggregator** | Test only | Mock Chainlink ETH/USD price feed. |

## Merchant Token Lifecycle

```
  1. PAY FEE          2. ADMIN APPROVES    3. USE / EXPIRE
  --------            ----------------     ---------------

  Merchant pays       Admin mints          Merchant can
  $20 in ETH          soulbound token      receive + burn
  (via Chainlink)     with expiry date     Littercoin

                      Admin can also:
                      - Extend expiry
                      - Invalidate
```

## Roles

| Role | Can Do | Cannot Do |
|---|---|---|
| **User** | Mint Littercoin (with signature), transfer to merchants, donate ETH | Burn Littercoin, mint while holding a Merchant Token |
| **Merchant** | Receive Littercoin, burn for ETH (minus 4.20% tax) | Mint Littercoin, transfer Littercoin |
| **Admin** | Approve/invalidate/renew merchants, sign mints, pause contracts | — |

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
npx hardhat compile
npx hardhat test
npx hardhat test --grep "burn tax"
```

### Tech Stack

- **Solidity** 0.8.27 (Cancun EVM)
- **OpenZeppelin** Contracts v5
- **Chainlink** price feed (ETH/USD)
- **Hardhat** with hardhat-toolbox
- **Tests**: JavaScript (Mocha/Chai), ethers.js v6
- **48 tests** covering all flows

## License

MIT
