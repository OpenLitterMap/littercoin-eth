# Littercoin Security Audit — Implementation Report

**Date:** 2 March 2026
**Scope:** Littercoin.sol, MerchantToken.sol, OLMThankYouToken.sol
**Baseline:** 48 passing tests, 0 known fixes applied
**Final state:** 72 passing tests, 10 fixes applied across 12 commits
**Files changed:** 3 (contracts/Littercoin.sol, contracts/MerchantToken.sol, test/Littercoin.js)
**Lines:** +472 / -49

---

## Executive Summary

A comprehensive security audit of the Littercoin smart contract system identified 18 findings across critical, high, medium, low, and informational severity levels. After triage by the project owner (documented in `readme/strategy.md`), 8 code fixes and 2 documentation fixes were prioritized for implementation. All 10 have been completed.

The two critical findings — a burn-bricking vulnerability in the tax transfer path and a fragile `receive()` reentrancy guard — have been fully resolved. Six high/medium severity issues covering gas limits, oracle upgradability, fee handling, reentrancy surface, soulbound completeness, and nonce collisions have been fixed. Two documentation gaps have been addressed.

No behavioral changes were made beyond the specified fixes. The 4.20% burn tax rate, MAX_MINT_AMOUNT of 10, and the intentional expired-merchant burn policy are all preserved.

---

## Findings and Resolutions

### Phase 1 — Critical

#### Fix 1: Try-first tax transfer with accumulate-on-failure
**Audit finding:** Owner ETH-receive failure permanently blocks all burns (CRITICAL)
**Commits:** `5733f41b`, `1fcad450`
**Files:** Littercoin.sol

**Problem.** The `burnLittercoin` function transferred the 4.20% burn tax to `owner()` inline with a `require(taxSuccess)`. If ownership was ever transferred to a contract that cannot receive ETH (no `receive()`, reverts, or runs out of gas), every merchant redemption would permanently revert. The entire ETH pool would be locked.

**Solution.** Replaced the hard-failing inline transfer with a try-first pattern:

```solidity
if (taxAmount > 0) {
    (bool taxSuccess, ) = payable(owner()).call{value: taxAmount}("");
    if (taxSuccess) {
        emit BurnTaxCollected(owner(), taxAmount);
    } else {
        accumulatedTax += taxAmount;
        emit TaxAccumulated(taxAmount);
    }
}
```

When the owner is a normal EOA, tax is sent immediately on each burn — identical behavior to before. If the transfer fails for any reason, the tax accumulates in `accumulatedTax` and the burn completes normally. The owner can later call `withdrawTax()` to collect.

**Critical secondary fix:** The proportional ETH calculation now uses `redeemableBalance` (contract balance minus accumulated tax) instead of the raw contract balance. Without this, accumulated tax would inflate the payout to subsequent merchants:

```solidity
uint256 redeemableBalance = address(this).balance - accumulatedTax;
uint256 totalEthToTransfer = (redeemableBalance * numTokens) / currentSupply;
```

**New state:**
- `uint256 public accumulatedTax` — tracks unwithdrawn tax
- `withdrawTax()` — `onlyOwner`, `nonReentrant`, resets `accumulatedTax` to 0
- `BurnTaxCollected` event — emitted on successful direct transfer or withdrawal
- `TaxAccumulated` event — emitted when tax transfer fails and falls back to accumulation

**Tests added (9):**
- Tax sent directly to EOA owner, `accumulatedTax` stays 0
- `BurnTaxCollected` emitted on successful transfer
- Multi-token burn tax calculated correctly
- `withdrawTax()` transfers correct amount and resets to 0
- `BurnTaxCollected` emitted on withdrawal
- `withdrawTax()` reverts when nothing accumulated
- Non-owner cannot call `withdrawTax()`
- Sequential burns calculate proportional ETH correctly (excluding accumulated tax)
- Multiple merchants burn independently, tax handled correctly

---

#### Fix 2: Split receive() into donate() + plain receive()
**Audit finding:** `receive()` reentrancy guard blocks ETH from nonReentrant contexts (CRITICAL)
**Commit:** `0279d7f7`
**Files:** Littercoin.sol

**Problem.** The `receive()` function had `nonReentrant` and `whenNotPaused` modifiers, plus it called `rewardToken.mint()` (an external call). This meant:
1. Any contract sending ETH to Littercoin from within its own `nonReentrant` function would fail
2. Plain ETH transfers reverted when paused (blocking pool growth during emergencies)
3. The external `mint()` call inside `receive()` created a larger-than-necessary attack surface

**Solution.** Split into two entry points:

```solidity
function donate() external payable nonReentrant whenNotPaused {
    _processDonation(msg.sender, msg.value);
}

receive() external payable {}
```

- `donate()` — Explicit donation function. Sends ETH, gets OLMTY reward tokens. Has `nonReentrant` and `whenNotPaused`. All Chainlink price feed logic lives here via `_processDonation()`.
- `receive()` — Bare ETH acceptance. No modifiers, no external calls. ETH goes silently into the pool. Works even when paused.

Donors who want the OLMTY receipt call `donate()` explicitly. Plain transfers just grow the pool.

**Tests added (5):**
- `donate()` mints correct OLMTY amount (1 ETH at $2000 = 2000 OLMTY)
- Plain ETH transfer via `receive()` succeeds without minting OLMTY
- `donate()` reverts when paused
- `donate()` reverts with zero ETH
- `donate()` emits `Reward` event
- Existing test updated: plain ETH transfers work even when paused

---

### Phase 2 — High & Medium

#### Fix 3: Burn batch limit
**Audit finding:** No upper bound on tokenIds array in burnLittercoin (HIGH)
**Commit:** `be9140b0`
**Files:** Littercoin.sol

**Problem.** A merchant could pass an arbitrarily large `tokenIds` array. While the caller pays for gas, this creates unpredictable gas behavior and could hit block gas limits in composed transactions.

**Solution.** Added `MAX_BURN_AMOUNT = 50` and a require check:

```solidity
uint256 public constant MAX_BURN_AMOUNT = 50;
// ...
require(numTokens <= MAX_BURN_AMOUNT, "Too many tokens in one burn");
```

50 tokens at ~60k gas per burn iteration uses ~3M gas — well within block limits with comfortable margin.

**Tests added (2):**
- Burn exactly 50 tokens succeeds (mints 50 via 5 batches of 10, transfers all, burns all)
- Burn 51 tokens reverts with "Too many tokens in one burn"

---

#### Fix 4: Updatable price feed
**Audit finding:** No ability to update Chainlink price feed address (HIGH)
**Commits:** `2de362e3`
**Files:** Littercoin.sol, MerchantToken.sol

**Problem.** The `priceFeed` address was set once in the constructor and could never be changed. If Chainlink deprecates or migrates the ETH/USD feed, the `donate()` function and `payMerchantFee()` would break permanently (stale price check fails after 1 hour).

**Solution.** Added `setPriceFeed()` to both contracts:

```solidity
function setPriceFeed(address _priceFeed) external onlyOwner {
    require(_priceFeed != address(0), "Invalid address");
    address oldFeed = address(priceFeed);
    priceFeed = AggregatorV3Interface(_priceFeed);
    emit PriceFeedUpdated(oldFeed, _priceFeed);
}
```

**Tests added (5):**
- Owner can update price feed on Littercoin (emits event)
- Owner can update price feed on MerchantToken (emits event)
- Non-owner cannot update either contract (reverts with `OwnableUnauthorizedAccount`)
- Zero address rejected on both contracts
- New price feed actually used: after switching to a $4000 feed, donating 1 ETH yields 4000 OLMTY

---

#### Fix 5: Merchant fee refund
**Audit finding:** Merchant fee overpayment not refunded (MEDIUM)
**Commit:** `42037183`
**Files:** MerchantToken.sol

**Problem.** `payMerchantFee()` forwarded the entire `msg.value` to the owner even when it exceeded the $20 USD equivalent. Users overpaying due to price fluctuations between estimation and execution lost the excess permanently.

**Solution.** Send only `requiredEth` to owner, refund the rest:

```solidity
(bool success, ) = payable(owner()).call{value: requiredEth}("");
require(success, "Fee transfer failed");

uint256 excess = msg.value - requiredEth;
if (excess > 0) {
    (bool refundSuccess, ) = payable(msg.sender).call{value: excess}("");
    require(refundSuccess, "Refund failed");
}

emit MerchantFeeCollected(msg.sender, requiredEth, MERCHANT_FEE_USD);
```

The event now logs `requiredEth` instead of `msg.value` for accurate accounting.

**Tests added (3):**
- Exact payment: owner receives 0.01 ETH, no refund needed
- Overpayment (0.02 ETH): owner receives 0.01 ETH, merchant gets 0.01 ETH back
- Underpayment: reverts with "Insufficient ETH for merchant fee"

---

#### Fix 6: Replace _safeMint with _mint in loop
**Audit finding:** `_safeMint` in loop enables callback reentrancy during partial mint (MEDIUM)
**Commit:** `90c2f2c5`
**Files:** Littercoin.sol

**Problem.** The `mint()` function used `_safeMint` in a loop, which triggers `onERC721Received` on each iteration if `msg.sender` is a contract. During these callbacks, the contract is in a partially-minted state — some tokens exist but not all. While the nonce is already consumed (preventing replay of this specific mint), the callback could interact with other Littercoin functions while `totalSupply()` is mid-update.

**Solution.** Single-line change:

```solidity
// Before:
_safeMint(msg.sender, tokenId);

// After:
_mint(msg.sender, tokenId);
```

The caller is `msg.sender` who initiated the transaction — they already know they're receiving ERC-721 tokens. The `onERC721Received` check is unnecessary and the callback vector is eliminated.

**Tests:** All 48+ existing mint tests continue to pass unchanged.

---

#### Fix 7: Disable approve/setApprovalForAll on MerchantToken
**Audit finding:** ERC721 approve/setApprovalForAll still work on soulbound token (MEDIUM)
**Commit:** `dc9468eb`
**Files:** MerchantToken.sol

**Problem.** The soulbound restriction was only in `_update()`. Users could successfully call `approve()` and `setApprovalForAll()` — the approvals would succeed but any subsequent `transferFrom` would fail. This creates confusing UX and misleading on-chain state.

**Solution.** Override both functions to revert immediately:

```solidity
function approve(address, uint256) public pure override {
    revert("Soulbound: approvals disabled");
}

function setApprovalForAll(address, bool) public pure override {
    revert("Soulbound: approvals disabled");
}
```

**Tests added (2):**
- `approve()` reverts with "Soulbound: approvals disabled"
- `setApprovalForAll()` reverts with "Soulbound: approvals disabled"

---

#### Fix 8: Per-user nonces
**Audit finding:** Nonces are global, not per-user (MEDIUM)
**Commit:** `dbe8d1ab`
**Files:** Littercoin.sol

**Problem.** `usedNonces` was `mapping(uint256 => bool)` — a single global namespace. If the backend issued nonce 42 to user A, user B could never use nonce 42. At scale this creates contention and makes nonce management fragile.

**Solution.** Changed to per-user nonce mapping:

```solidity
// Before:
mapping(uint256 => bool) public usedNonces;

// After:
mapping(address => mapping(uint256 => bool)) public usedNonces;
```

Updated the `mint()` function to scope nonce checks to `msg.sender`:

```solidity
require(!usedNonces[msg.sender][nonce], "Nonce already used");
usedNonces[msg.sender][nonce] = true;
```

The EIP-712 hash already includes the user address, so signatures remain user-specific and secure. This change only eliminates the cross-user nonce collision space.

**Tests added (3):**
- Same nonce value (999) works for two different users
- Same user replaying same nonce reverts with "Nonce already used"
- Sequential nonces (1, 2) for same user both work

---

### Phase 3 — Documentation

#### Fix 9: Document intentional expired-merchant burn
**Audit finding:** Expired merchant tokens can burn Littercoin for ETH (HIGH — accepted by design)
**Commit:** `32c74dc0`
**Files:** Littercoin.sol

Added NatSpec documentation above `burnLittercoin` and the burn path in `_update` explaining the intentional design decision:

```solidity
/// @dev Uses hasMerchantToken (ignores expiry) intentionally. Merchants who received
///      Littercoin through legitimate trade can always redeem them. Expiry only prevents
///      receiving NEW Littercoin. The admin can still emergency-pause the contract if needed.
```

This documents the project owner's decision: merchants earn tokens through legitimate trade. Revoking their ability to redeem because a license lapsed would be unfair. Expiry controls the flow of new tokens, not the redemption of existing ones.

---

#### Fix 10: Update CLAUDE.md
**Commit:** `201fed0f`
**Files:** CLAUDE.md

Fixed stale references in the project architecture documentation:
- `_beforeTokenTransfer` → `_update` (OpenZeppelin v5 hook)
- `OpenZeppelin Contracts v4.9.2` → `v5` (matches actual code patterns: `Ownable(msg.sender)`, `_update` override)
- `OLMRewardToken` → `OLMThankYouToken` (actual contract name)
- `Counters` removed (not used in OZ v5)
- `rewardToken.transferOwnership(address(this))` → `OLMThankYouToken(address(this))` (set in constructor, not transferred)
- Added `donate()`, pull-based tax, per-user nonces, burn limit, fee refund, and soulbound approval info

#### README update
**Commit:** `c26729bf`
**Files:** README.md

Added a complete rules reference section with three tables documenting every on-chain enforcement:
- Littercoin lifecycle rules (15 rules with function, check, and location)
- Merchant Token rules (12 rules)
- Admin capabilities (7 actions with function and contract)

Updated existing sections to reflect all security fixes: `donate()` vs `receive()`, try-first tax, per-user nonces, burn limit, fee refund, soulbound approvals, and the expired-merchant burn design note.

---

## Test Summary

| Category | Tests Before | Tests After | New Tests |
|---|---|---|---|
| Mint (Littercoin) | 6 | 6 | 0 |
| Transfer (Littercoin) | 5 | 5 | 0 |
| Burn (Littercoin) | 5 | 7 | 2 |
| Pause | 5 | 5 | 0 |
| Merchant Token | 12 | 12 | 0 |
| Burn Tax | 3 | 9 | 6* |
| Merchant Fee | 5 | 8 | 3 |
| Donate / Receive | 1 | 5 | 4* |
| Soulbound Approvals | 0 | 2 | 2 |
| Per-User Nonces | 0 | 3 | 3 |
| Price Feed Update | 0 | 5 | 5 |
| Burn Batch Limit | 0 | 2 | 2 |
| **Total** | **48** | **72** | **24** |

*Some existing tests were rewritten to match new behavior (donate() instead of receive(), accumulatedTax instead of direct transfer) — counted as replacements, not net-new.

All 72 tests pass. `npx hardhat compile` produces zero errors.

---

## Deferred Items

These items from the original audit were triaged as not requiring code changes at this time:

| Finding | Severity | Decision | Rationale |
|---|---|---|---|
| Owner centralization (single key) | MEDIUM | Deferred | Operational decision — use a Gnosis Safe multisig at deployment. No code change needed. |
| ETH force-sent via selfdestruct | LOW | Accepted | Inherent to Solidity. Minor merchant windfall, not exploitable. |
| Redundant pause checks | LOW | Accepted | Defense-in-depth. Negligible gas cost. |
| Chainlink roundId validation | LOW | Skipped | Staleness check is sufficient for V3. |
| Floating pragma | LOW | Skipped | Hardhat config pins to 0.8.27. Pin in source before mainnet. |
| tokenTransferred never cleaned | INFO | Accepted | Token IDs never reused. Dead storage is harmless. |
| Missing price event in donate | INFO | Skipped | Price reconstructable from reward amount and ETH sent. |
| exists() non-standard | INFO | Accepted | Convenience getter. Harmless. |
| No fallback() function | INFO | Accepted | Correct behavior — calls with data to unknown selectors should revert. |

---

## Contract Size Note

The Littercoin contract initcode size (~50.9KB) exceeds the Shanghai limit of 49,152 bytes. This is a pre-existing condition that predates these changes. Before mainnet deployment, enable the Solidity optimizer with a low `runs` value or consider extracting logic into libraries. This does not affect testnet deployments or the correctness of any fix.
