# Pipo First Spark #72 — Offline source slice (native validation pending)

**Date:** 2026-11-23. **Status:** Draft source-only, **NOT** native-QA-passed. Mac runner paused by product owner.

## Canonical approved motion references

- [First Spark Motion V1 · 780 ms](https://www.figma.com/design/tce3nRBcRwyObJMwQzA2rK/Gamification-Saving-SaaS?node-id=1606-19442)
- [Reduce Motion static success](https://www.figma.com/design/tce3nRBcRwyObJMwQzA2rK/Gamification-Saving-SaaS?node-id=1609-20076)
- [Motion QA acceptance](https://www.figma.com/design/tce3nRBcRwyObJMwQzA2rK/Gamification-Saving-SaaS?node-id=1602-19444)
- [Approved source poses #71](https://www.figma.com/design/tce3nRBcRwyObJMwQzA2rK/Gamification-Saving-SaaS?node-id=1529-7055)

## Implemented

1. A pure, presentation-only eligibility check `PipoFirstSparkEligibility.forCommittedFirstPeriod` rejects wrong account/goal, flexible/group goals, invalid/future amounts, duplicate/replayed UUIDs and any already-recorded contribution on that goal. It uses `SavingConsistency.periodIndex`; it does not mutate streaks, XP, badges, currencies, or transactions.
2. The existing save sheet sets the First Spark flag **only after** `try modelContext.save()` succeeds. Rejected/failed writes never prepare a reward, and the callback runs only if the same owner still holds the goal when the saving sheet closes.
3. `NavigationManager` carries this single-presentation flag, clears it on account reset, and replaces it on every new confirmed save. Merely creating/opening a goal cannot trigger it.
4. `ConsistencyMilestoneView` has a self-contained scene: Idle → Notice → Reach → Hug → Mini Jump → Settle, event sequence programmed on a 780 ms schedule, non-looping. It uses already-bundled `PipoV4Neutral` and Spark icon; **it is a conservative full-image/source-art placeholder, not a claim of correct anatomical keyframes**. No external webview or network playback was introduced.
5. The system Reduce Motion setting renders a static composition with the same result copy. App-background transitions settle the scene rather than replay it.
6. Three authored XCTest regressions and `scripts/test_issue72_first_spark_contract.py` (Linux only). Only Linux static checks can be considered completed before Xcode is re-enabled.

## Deliberate constraints

- Global `firstSave` badge is distinct from goal-specific first scheduled period: no false badge claims.
- No First Spark for flexible saving, where there is no scheduled streak period.
- No animation on failed save, duplicate journal replay, navigation-only events, auth switch or process relaunch. UI still needs actual native regression proof before this is considered verified.
- No change to SwiftData schema or real payment, entitlement, CAS, Money Out or Supabase operations.
- Initial partial animation is **not** the approved 18-frame anatomical artwork; #71's missing near-hoof/HugSpark exports and actual pose interpolation require separate licensed exports and owner visual signoff.

## Next verification, when Mac runner is explicitly re-enabled

- Exact-head Swift compilation and three XCTest regressions, as well as UI tests for first eligible event, second saving same period, later goals, failed save, account switch and app relaunch.
- Native MP4 at 30/60fps as available, 780 ms frame sequence review against Figma, no anatomy break, correct near-hoof contact and easing; verify 320pt/393pt, Dynamic Type, VoiceOver, Reduce Motion, background/foreground, low power and safe areas.
- Fix layout issues observed in previous PR #95 visual review across shared overlays/footers before a final merged release batch.
- Obtain user's one final merge approval. **Do not mark this Draft PR ready, merge, deploy, activate payment or run macOS automatically.**
