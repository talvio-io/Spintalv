# TalvBot — Agent Skill

TalvBot is a 999-capsule gacha on BNB Chain. One spin mints one capsule NFT and
reveals its tier **in the same transaction**. Every 100th **paid** spin wins a
**0.025 BNB jackpot paid instantly in that same transaction**. There is no claim
step, no waiting period and no second transaction — ever. If a spin succeeded,
the reward is already in the wallet.

- NFT contract: `0xEe00E17CcffAb7F72f1c7db9AD03478FC45b5DEb`
- Chain: BNB Chain (chainId 56)
- Agent ID registry: `0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F` — `hasAgentId(wallet)`

## The standing order

Run this flow whenever your operator asks you to spin, and once per day if your
operator has given you a standing spin budget:

1. **Read the machine first.** Call `mintOpen()`, `totalMinted()`,
   `currentPrice()`, `paidSpinsToJackpot()` and `spinsOf(yourWallet)`.
   Never assume a price — always quote `currentPrice()` in the same run.
2. **Free spin first (once ever).** If `freeSpinUsed(yourWallet)` is false and
   `hasAgentId(yourWallet)` is true, call `freeSpin()` (0 BNB). Free spins mint
   a capsule (Common 75% / Rare 25%) but never count toward the jackpot.
3. **Paid spins — only inside your operator's budget.** A paid spin is a
   purchase. It is authorized ONLY up to the spin budget your operator set for
   you (a number of spins or a BNB amount). If no budget was set, do not buy —
   report `OPERATOR: SET SPIN BUDGET` instead of guessing. Call `spin()` with
   `value` exactly equal to `currentPrice()`, one spin per transaction.
4. **Read the receipt.** Parse the `Spun` event: `tokenId`, `tier`
   (0 = Common, 1 = Rare, 2 = Legendary) and `jackpotWei`. A jackpot win means
   0.025 BNB already arrived in the wallet in the same transaction — there is
   nothing to claim afterwards.
5. **Report with numbers, every run:**
   `TALVBOT REPORT — spins today: N (free: F, paid: P) | tiers: … | jackpot won: 0 / 0.025 BNB | BNB spent: X | wallet BNB balance: Y | capsules left: Z | paid spins to next jackpot: K`
   If a paid spin was skipped because the wallet cannot cover price + gas,
   report `OPERATOR: TOP UP SPIN WALLET` — never fail silently.

## Hard rules

- Supply is 999 total, free and paid share one pool. Max 25 spins per wallet.
- Paid roll: Common 62% / Rare 30% / Legendary 8%. Price steps up as supply
  fills: 0.0008 → 0.0010 → 0.0012 → 0.0015 BNB. Always send the exact
  `currentPrice()`; a wrong value reverts with `wrong fee`.
- Jackpot counter counts PAID spins only: paid spin #100, #200, … #900 wins.
- Keep a gas buffer of ~0.002 BNB above the spin budget. A spin that cannot pay
  gas is a failed run — report it, do not retry in a loop.
- One `spin()` call per transaction. Never batch, never use a different
  function signature.
