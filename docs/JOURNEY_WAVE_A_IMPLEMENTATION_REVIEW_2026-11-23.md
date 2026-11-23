# Pipo Journey & Achievements — Approved Wave A Implementation Handoff

**Prepared:** 2026-11-23. **Status:** isolated implementation, pending exact-head CI, simulator screenshot comparison and owner final source merge approval. **Base:** `main` after PR #92 and PR #94, merge SHA `63c0f262c345f2601061926cb052b6f8426a6d49`. Original design-only [PR #93](https://github.com/muhammadihsan-byte/pipo-gamification/pull/93) is separate; it is **not** a feature or safe auto-merge.

Approved Figma: [Ihsan Space section 10 — Journey & Achievements](https://www.figma.com/design/tce3nRBcRwyObJMwQzA2rK/Gamification-Saving-SaaS?node-id=1849-11284). Implementation borrows the existing native Pipo `TicketCard`, color tokens, `PipoV4HeadCrop`, badge assets, Goal Details routing and `AchievementEngine` rather than duplicating them.

## Implemented in Wave A (no UI approval/merge implied)

| Figma screen | Status | Source behavior |
|---|---|---|
| 01 Your Saving Story | Implemented | This-month actual contribution count, exact single-currency subtotal or **separate per-currency totals** (never mixed FX), persisted XP from contributions only, two latest real entries, badge collection and honest manual disclosure |
| 02 Timeline (3 saving events) | Implemented | Calendar-based month filter; genuine owner-scoped and stable-ID sorted entries; tappable safe read-only Saving Detail. **No fictional milestone row** without a durable earned-at event |
| 03 Achievements / earned collection | Implemented | Earned badge artwork and current saved profile IDs in a collection grid; upcoming milestone and locked/coming later states; **no fabricated award date or unbuilt badge detail tap** |
| 05 Zero entries for owned goal | Implemented | Owner's actual goal title, currency, progress and existing Goal Detail navigation, calm zero-pressure wording |
| 06 No owned goals | Implemented | Create Goal existing flow, steps, manual/no-bank-disclosure; no money movement |
| 09 Full Timeline / All Time | Implemented | No `prefix(12)` truncation; month grouping and calendar-aware current-month vs all-time selection |

**Wave B later:** 04 Quarter Way badge detail; 08 real completed-goal experience; 10 First Step detail; 11 real completed story with non-replaying celebration. **Deferred:** 07 Money Taken Out; requires approved immutable events and account-safe save contracts (#42/#80) and is not synthesised by this PR.

## Implementation safety

- `PipoJourneyProjection.entries` rechecks owner-scoped goal and transaction identities via `AccountScope`, quarantines ownerless rows, deduplicates UUIDs, sorts latest first and ties by stable UUID.
- Monthly selection uses `Calendar.dateInterval(of: .month, for: now)`, not rolling 30 days; `All time` is never truncated.
- Exact monetary subtotal uses per-currency minor units, validates ISO support and positive amounts; on overflow, invalid legacy precision or any malformed amount, suppresses partial totals rather than silently summing disparate currencies.
- Badges are read from persisted `UserProfile.unlockedBadgeIds`; the original reward engine remains unique. The view has **zero writes** to saving transactions, goals, XP or achievements.
- Existing goal navigation, create-goal flow and badge sheet are reused. One recording detail uses a read-only owned record validation and never starts Money Out.
- On auth changes Dashboard clears the selected record sheet and the Journey view resets filter/navigation state. No presentation can disclose account A's history to B.
- Screenshot reference uses approved Figma frames; the Figma asset paths are NOT embedded in code. Existing exact approved badge and Pipo V4 image assets are reused.

## Validation matrix

- Native XCTest `PipoJourneyWaveAProjectionTests`: A/B owner isolation, ownerless exclusion, duplicate UUID, timezone/month boundary, tie sort, >12 historical entries, multi-currency exact subtotals, zero synthetic XP or badge grants.
- Native UI XCTest `testJourneyWaveAEmptyStatesAndRealHistory`: real synthetic Debug account flow → no-goals screenshot → real created goal no-records screenshot → persisted manual saving and app-process relaunch → story screenshot → All Time/Month filters → real record details → earned/locked collection screenshot. It uses an isolated local SwiftData QA store, no backend credentials or financial transfer.
- Controlled `ios-build.yml` PR-specific step records MP4 and exports XCTest screenshot attachments into existing 7-day GitHub Actions artifacts. The branch must become *Ready for review* once **after** cheap Linux checks to start this single native simulator batch.
- PR Fast Checks, native build/unit tests, focused UI QA, accessibility tree and visual parity must be reviewed on the same exact SHA. Real-device VoiceOver remains a separate App Store release gate.

## Review/merge gate

1. Check PR Fast Checks static baseline; do not interpret skip as native success.
2. Run the single simulator QA batch, inspect actual screenshots at 320pt/standard size and compare to Figma; fix any in-scope issues on this isolated branch.
3. Obtain the user's **one final merge approval**. No automatic merge, release flag changes, Supabase production SQL, StoreKit or TestFlight rollout.

**User trust:** All displayed amounts are manually recorded, not bank verified. Do not create fake historic transactions or milestone timestamps for a closer screenshot match.
