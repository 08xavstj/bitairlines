# Rewarded ads: where they fit

A plan, not code yet. The rule that shapes it: Apple, Google AdMob and AppLovin all require a rewarded ad to be the
player's choice. The game may not force one, hide progress behind one, or nag. What makes people choose to watch is a reward
that is worth more than 30 seconds at exactly the moment they want it. Competitor reviews (docs/review-2026-10.md) show
players accept ads like this and punish forced ones.

## Placements, best first

| # | Moment | Offer | Why it works | Limit |
|---|---|---|---|---|
| 1 | The game stops because the bank balance is below zero (overdraft issue) | "Watch an ad: a sponsor covers one week of head office" next to the emergency loan | The player is worried and the reward solves the problem | Once per overdraft |
| 2 | A breakdown pauses the game | "Watch an ad: the mechanic flies in free" (repair cost waived) | A clear, immediate saving | Once per breakdown |
| 3 | A job on the Jobs board | "Watch an ad: double the pay" on one job | The player already wants the job | One job a day |
| 4 | Jobs board is thin | "Watch an ad: new jobs now" (re-roll the board) | Gives choice, not money | Once a day |
| 5 | Coming back after a break (needs a "while you were away" summary first) | "Watch an ad: double today's landing fees back" | The idle-game standard: Kolibri's games are built on it | Once a day |
| 6 | Hangar listings | "Watch an ad: see this week's extra listings" (two more used aircraft) | A rare aircraft is a strong pull | Once a week |

Keep the total to about 6 a day. Size every cash reward to the airline (for example one day of the airline's average
operating profit, with a floor), so it stays worth watching at level 7 and never breaks the economy at level 1.

## Never

- An ad that plays without a tap, or between screens (interstitials).
- A reward the game cannot be finished without.
- Selling aircraft or levels for real money (pay-to-win is the top complaint in the genre).
- Energy timers or waits invented to sell skips.

## How to build it later

1. Core: a `RewardKind` enum and `World.grantReward(_:)` that applies the reward deterministically (no randomness, no
   clock), with a daily counter in `Operations`. Tests check each reward and the daily limits.
2. App: an `AdService` protocol with `func showRewarded(completion: (Bool) -> Void)`. A stub that always returns true for
   development, and one real implementation (Google AdMob or AppLovin MAX) behind it.
3. Buttons only appear when an ad is loaded. If the ad fails, nothing is lost and the button says so.
4. A one-time purchase, "Pilot's licence" ($3.99 to $4.99), removes the need to watch: each offer becomes a plain button.
   Players praise this model; it must have Restore Purchases.
5. Compliance: App Tracking Transparency prompt (personalised ads only after "Allow"), SKAdNetwork IDs, the SDK's privacy
   manifest, App Privacy label updated, no ads for players under 13 (ask the age gate the ad network requires).
