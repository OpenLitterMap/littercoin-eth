# Littercoin

**An exchangeless, non-tradable climate currency on Ethereum.**

> **Status: In development — not yet audited.**

## What is Littercoin?

Littercoin is a token that turns environmental
data collection into real economic value — but only
within a zero-waste economy.

Every Littercoin is an NFT backed by real ETH. You earn
it by collecting and documenting litter data on
[OpenLitterMap](https://openlittermap.com), a
UN-recognized Digital Public Good.

Littercoin is different. You cannot send it to
anyone. The only thing you can do with Littercoin is
spend it with verified ecomerchants — zero-waste
businesses that we approve of, who don't use plastic.

If a Zero Waste Store or Ecomerchant wants new
customers, they need to apply for a MerchantNFT.
A Valid Merchant Token is needed to accept Littercoin.
You can only send Littercoin to people who have a valid MerchantNFT.

Merchants with a Valid Token can send Littercoin to the Smart Contract in exchange for ETH.

Littercoin gets its value from donations. If people
send ETH to the contract, the value of Littercoin grows.
Donations are are rewarded with OLMThankYouTokens — 1 OLMTY for every $1 of ETH.

Littercoin intends to be unlike most cryptos. There is no ICO,
no pre-mine, and no exchanges. Littercoin cannot be
bought, sold, or traded. It can only be earned & spent
with a zero-waste merchant. Each Littercoin has a lifecycle of
exactly 3 transactions. Earn, Spend, Burn.
Any other tx will invalidate the token.

## Why does the data matter?

Every upload to OpenLitterMap is a geotagged,
categorized environmental observation — structured
data that municipalities, academics, and
community groups can use to monitor pollution patterns,
enforce taxes, educate society, allocate resources, and measure policy outcomes & behaviour trends.

OpenLitterMap has 500,000+ observations. 110+ countries. Cited in 100+
academic publications. Littercoin turns this data contribution into economic worth.

## Who earns Littercoin?

Users earn Littercoin by uploading verified
litter data to OpenLitterMap.
100 uploads = 1 Littercoin.

The backend signs an EIP-712 message authorizing the
mint. The user submits it on-chain. No middleman
decides your balance — the signature proves you
earned it.

## How does it work?

Every Littercoin has exactly 3 transactions:

```
  1. MINT             2. TRANSFER          3. BURN
  -----              ----------           -----

  User collects       User sends           Merchant burns
  litter data,        Littercoin to        Littercoin and
  uploads to          an approved          receives ETH
  OpenLitterMap       zero-waste           from the pool
                      merchant
  Backend signs       (one time only)      4.20% burn tax
  EIP-712 message                          goes to platform
  User claims
  on-chain
  (max 10 per tx)
```

The contract enforces every rule:

- **Merchants cannot mint.** If you hold a valid
  Merchant Token, the contract blocks you from minting.
- **Users can only transfer to merchants.** Each token
  can be transferred exactly once, and only to an
  address with a valid (non-expired) Merchant Token.
- **Only merchants can burn.** Burning redeems
  proportional ETH from the pool.
- **Merchants cannot transfer.** Once a merchant
  receives Littercoin, they can only burn it.

Any transfer that violates these rules is rejected.

## How does it have value?

```
  DONORS             USERS              MERCHANTS
    |                  |                    |
    | Send ETH         | Collect data,     |
    | to contract      | upload to OLM,    |
    v                  | earn Littercoin    |
                       v                    |
  +--------------------+--------------------+
  |                                         |
  |         Littercoin Contract             |
  |         (ETH Pool)                      |
  |                                         |
  |   Pool Balance / Total Supply           |
  |   = Value Per Token                     |
  |                                         |
  +--------------------+--------------------+
                       |                    |
                       | Transfer           | Burn
                       | Littercoin         | Littercoin
                       | to merchant        | for ETH
                       v                    v
                    MERCHANT           ETH PAYOUT
                    WALLET          95.80% merchant
                                     4.20% platform
```

Anyone can donate ETH to the contract. When they do,
donors receive OLM Thank You Tokens ($1 donated = 1
OLMTY) as a receipt.

The ETH pool backs every Littercoin in circulation.
More donations mean a higher value per token, which
means a stronger incentive to collect data.

When a merchant burns Littercoin, they receive
their proportional share of the pool minus a 4.20%
platform fee.

## Zero-waste merchants

Not just any business can accept Littercoin. Merchants
must be approved zero-waste businesses — businesses
that don't use plastic.

```
  1. PAY FEE          2. ADMIN APPROVES    3. USE / EXPIRE
  --------            ----------------     ---------------

  Merchant pays       Admin mints          Merchant can
  $20 in ETH          soulbound token      receive + burn
  (via Chainlink      with expiry date     Littercoin
  price feed)
                      Admin can also:      After expiry,
                      - Extend expiry      merchant can
                      - Invalidate         still burn held
                                           tokens but
                                           cannot receive
                                           new ones
```

The Merchant Token is soulbound (non-transferable),
limited to one per address, and has an expiration date.
This means merchant status must be actively maintained.

## Revenue model

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

## Roles

| Role | Can Do | Cannot Do |
|---|---|---|
| **User** | Mint Littercoin (with signature), transfer to merchants, donate ETH | Burn Littercoin, mint while holding a valid Merchant Token |
| **Merchant** | Receive Littercoin (while valid), burn for ETH (minus 4.20% tax) | Mint Littercoin, transfer Littercoin |
| **Admin** | Approve/invalidate/renew merchants, sign mints, pause contracts | — |

## Development

### Prerequisites

- Node.js
- npm

### Setup

```bash
npm install
```

### Build and test

```bash
npx hardhat compile
npx hardhat test
npx hardhat test --grep "burn tax"
```

### Tech stack

- **Solidity** 0.8.27 (Cancun EVM)
- **OpenZeppelin** Contracts v5
- **Chainlink** price feed (ETH/USD)
- **Hardhat** with hardhat-toolbox
- **Tests**: JavaScript (Mocha/Chai), ethers.js v6

## License

MIT