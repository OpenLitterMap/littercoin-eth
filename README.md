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

The contract enforces every rule on-chain. No exceptions.

### Minting rules
- Only users (non-merchants) can mint
- Requires a valid EIP-712 signature from the backend (owner)
- Max 10 tokens per transaction (`MAX_MINT_AMOUNT`)
- Nonces are per-user: each user has their own nonce space
- Signature must not be expired (`block.timestamp <= expiry`)
- Merchants (addresses holding a valid, non-expired Merchant Token) are blocked from minting

### Transfer rules
- Each Littercoin can be transferred exactly once
- Sender must NOT be a merchant (merchants cannot forward tokens)
- Recipient MUST hold a valid (non-expired) Merchant Token
- `tokenTransferred[tokenId]` is set to `true` after transfer — irreversible

### Burn rules
- Only addresses holding a Merchant Token can burn (expiry is ignored — see design note below)
- Caller must own every token in the `tokenIds` array
- Max 50 tokens per burn transaction (`MAX_BURN_AMOUNT`)
- ETH payout = `(redeemableBalance * numTokens) / totalSupply`
- Redeemable balance = `address(this).balance - accumulatedTax`
- 4.20% burn tax is deducted from the payout
- Tax is tried as a direct transfer to owner first; on failure it accumulates for pull-based withdrawal

### Donation rules
- `donate()` — sends ETH and receives OLMThankYouTokens (1 OLMTY per $1 USD, via Chainlink)
- `receive()` — accepts plain ETH silently into the pool (no reward tokens)
- Donors who want the OLMTY receipt must call `donate()` explicitly

### Pause rules
- Owner can pause/unpause the contract
- When paused: minting, burning, transferring, and `donate()` are all blocked
- Plain `receive()` still works when paused (pool can still grow)

### Design note: expired merchants CAN burn
Merchants who received Littercoin through legitimate trade can always
redeem them, even after their Merchant Token expires. Expiry only
prevents receiving NEW Littercoin. This is intentional — you don't
void someone's inventory because their license lapsed. The admin
can still emergency-pause the contract if needed.

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

Anyone can add ETH to the contract pool in two ways:

- **`donate()`** — Sends ETH and mints OLM Thank You Tokens
  ($1 donated = 1 OLMTY) as a receipt. Requires a fresh Chainlink
  price feed (< 1 hour old). Has reentrancy protection.
- **Plain ETH transfer** — ETH goes silently into the pool.
  No reward tokens are minted. Works even when paused.

The ETH pool backs every Littercoin in circulation.
More donations mean a higher value per token, which
means a stronger incentive to collect data.

When a merchant burns Littercoin, they receive their
proportional share of the redeemable pool (excluding
any accumulated tax) minus a 4.20% platform fee.

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
  Excess ETH is       - Extend expiry      merchant can
  refunded auto-      - Invalidate         still burn held
  matically                                tokens but
                                           cannot receive
                                           new ones
```

The Merchant Token is soulbound — transfers and approvals
(`approve`, `setApprovalForAll`) are disabled at the contract
level. Limited to one per address with an expiration date.
Merchant status must be actively maintained.

## Revenue model

```
  BURN TAX (4.20%)
  ----------------
  Every time a merchant burns
  Littercoin for ETH:

  Total ETH payout
    |
    +-- 95.80% --> Merchant
    +--  4.20% --> Try send to owner
                    |
                    +-- Success: sent immediately
                    +-- Failure: accumulated in contract
                        (owner calls withdrawTax() later)


  MERCHANT FEE ($20)
  ------------------
  Zero-waste merchants pay $20
  in ETH to apply for approval:

  Merchant pays fee ($20 in ETH via Chainlink)
    |
    +-- $20 ETH  --> Platform owner
    +-- Excess   --> Refunded to merchant
    |
  Admin approves
    |
    +-- Merchant Token minted
```

## Contracts

```
  Littercoin (ERC-721)
  Main contract. Holds ETH pool.
  Deploys child contracts on construction.
  |
  +-- OLMThankYouToken (ERC-20)
  |   Minted to donors via donate().
  |   $1 donated = 1 OLMTY.
  |   Owned by Littercoin contract.
  |
  +-- MerchantToken (ERC-721)
      Soulbound. Transfers + approvals disabled.
      One per address. Has expiry.
      $20 fee to apply (excess refunded).
      Owned by admin (deployer).
```

| Contract | Type | Purpose |
|---|---|---|
| **Littercoin** | ERC-721 Enumerable | Main token. Mint via EIP-712 (per-user nonces), transfer to merchants, burn for ETH (max 50/tx). Holds the ETH pool. 4.20% burn tax (try-first, accumulate-on-failure). `donate()` for OLMTY rewards. `receive()` for silent pool growth. |
| **MerchantToken** | ERC-721 Soulbound | Non-transferable, approvals disabled. $20 fee (with refund) + admin approval. Expiration timestamp. One per address. Updatable price feed. |
| **OLMThankYouToken** | ERC-20 | Minted when ETH is donated via `donate()`. 1 OLMTY per $1 USD (via Chainlink). |
| **MockV3Aggregator** | Test only | Mock Chainlink ETH/USD price feed. |

## Roles

| Role | Can Do | Cannot Do |
|---|---|---|
| **User** | Mint Littercoin (with signature), transfer to merchants, call `donate()` | Burn Littercoin, mint while holding a valid Merchant Token |
| **Merchant** | Receive Littercoin (while valid), burn for ETH (even after expiry, minus 4.20% tax) | Mint Littercoin, transfer Littercoin, approve transfers |
| **Admin (Owner)** | Approve/invalidate/renew merchants, sign mints, pause/unpause, update price feed, withdraw accumulated tax | — |

## Complete Rules Reference

Every rule below is enforced on-chain. This is the canonical source of truth for what the contracts allow and reject.

### Littercoin lifecycle

```
RULE                                       ENFORCED IN           CHECK
───────────────────────────────────────────────────────────────────────────
Mint amount: 1-10 per tx                   mint()                amount > 0 && amount <= 10
Mint requires valid EIP-712 signature      mint()                ECDSA.recover == owner()
Mint nonces are per-user                   mint()                usedNonces[msg.sender][nonce]
Mint signature must not be expired         mint()                block.timestamp <= expiry
Merchants cannot mint                      _update (mint path)   !hasValidMerchantToken(to)
Each token transfers exactly once          _update (transfer)    !tokenTransferred[tokenId]
Sender must not be a merchant              _update (transfer)    !hasValidMerchantToken(from)
Recipient must be a valid merchant         _update (transfer)    hasValidMerchantToken(to)
Only merchants can burn                    _update (burn path)   hasMerchantToken(from)
Expired merchants CAN burn (intentional)   _update (burn path)   hasMerchantToken ignores expiry
Burn max 50 tokens per tx                  burnLittercoin()      numTokens <= MAX_BURN_AMOUNT
Caller must own all tokens being burned    burnLittercoin()      ownerOf(tokenId) == msg.sender
ETH payout excludes accumulated tax        burnLittercoin()      redeemableBalance = balance - accumulatedTax
4.20% burn tax (try-first, accumulate)     burnLittercoin()      try send to owner, else accumulatedTax +=
Paused blocks mint/transfer/burn/donate    _update, modifiers    whenNotPaused / _requireNotPaused
Plain ETH receive works even when paused   receive()             no modifiers
```

### Merchant Token rules

```
RULE                                       ENFORCED IN           CHECK
───────────────────────────────────────────────────────────────────────────
$20 USD fee required (via Chainlink)       payMerchantFee()      msg.value >= requiredEth
Excess ETH refunded automatically          payMerchantFee()      refund msg.value - requiredEth
Fee can only be paid once                  payMerchantFee()      !feePaid[msg.sender]
Must not already hold a token              payMerchantFee()      balanceOf(msg.sender) == 0
Only owner can mint tokens                 mint()                onlyOwner
Expiration must be in the future           mint()                expirationTimestamp > block.timestamp
One token per address                      mint()                balanceOf(to) == 0
Transfers are disabled (soulbound)         _update()             revert if from != 0 && to != 0
Approvals are disabled                     approve/setApproval   always reverts
Owner can extend expiry                    addExpirationTime()   onlyOwner
Owner can invalidate                       invalidateToken()     onlyOwner, sets expiry to past
Holder can self-burn                       burn()                tokenId from _ownedTokenId[msg.sender]
```

### Admin capabilities

```
ACTION                     FUNCTION              CONTRACT
───────────────────────────────────────────────────────────────────────────
Sign mint authorizations   (off-chain EIP-712)   Littercoin
Pause / unpause            pause(), unpause()    Littercoin, MerchantToken
Withdraw accumulated tax   withdrawTax()         Littercoin
Update price feed          setPriceFeed()        Littercoin, MerchantToken
Approve merchant           mint()                MerchantToken
Extend merchant expiry     addExpirationTime()   MerchantToken
Invalidate merchant        invalidateToken()     MerchantToken
```

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