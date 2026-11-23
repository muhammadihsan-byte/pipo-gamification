# Pipo — Saving Journey & Achievements: approved UI handoff preparation

**Status:** Documentation-only preparation / implementation **not started** / no feature merge approval  
**Prepared:** 23 Nov 2026  
**Read baseline:** `main` at `5995e89796345a4ca8740c7e75b71d7349b1c8dc`  
**Canonical design:** [Ihsan Space section 10 — 11 approved Journey & Achievements screens](https://www.figma.com/design/tce3nRBcRwyObJMwQzA2rK/Gamification-Saving-SaaS?node-id=1849-11284)  
**Deferred implementation register:** [Ihsan Space section 19](https://www.figma.com/design/tce3nRBcRwyObJMwQzA2rK/Gamification-Saving-SaaS?node-id=2039-21120)  
**Existing issue:** [#41 — Goal Detail / Journey UX](https://github.com/muhammadihsan-byte/pipo-gamification/issues/41). Also #15 achievement integrity, #14 rhythms, #16 correction and #21 lifecycle.

> This document maps UI approval to **candidate** implementation work. Approval of Figma visuals does not authorize live Money Out, fictional events, paid features, database mutations, App Store release, TestFlight or a merge. **Do not create a duplicate feature PR until the existing integration PR #92 is dispositioned and main parity is rechecked.**

## 1. Baseline findings (verified)

- `Pipo/Features/Dashboard/ContentView.swift` already has a real Journey tab (`journeyPage`) and `achievementsSheet` using account-scoped `ownedGoals`, `ownedTransactions` and `currentProfile?.unlockedBadgeIds`.
- `Pipo/Core/DesignSystem/PipoApprovedCards.swift` already implements `PipoMilestonesDCard` (existing First Step and Quarter Way shelf) and `PipoActivityHistoryDCard` (up to 12 genuine saving records, with per-event currency and a manual-record disclaimer). **This is not the approved multi-screen timeline.**
- `Pipo/Core/Gamification/GamificationManager.swift` contains `PipoBadge` and `AchievementEngine.grant` with existing persisted-event eligibility/replay safety. Keep one reward engine; do not grant XP or badges in view rendering.
- `PipoUITests/PipoUIRecordingTests.swift` covers basic Journey navigation, existing achievement collection and first-save persistence. It does not prove all 11 approved visual/empty/detail/filter states.
- `PipoTests/GamificationManagerTests.swift` covers multiple unlock, account isolation, duplicate-event and streak cases. Extend existing tests rather than replacing them.
- Integration [PR #92](https://github.com/muhammadihsan-byte/pipo-gamification/pull/92) (includes #79 visual and #80 CAS/legacy proposals) is **open and unmerged** at preparation time; exact-head fast checks passed but a new iOS run was still in progress on inspection. It changes Dashboard account-switch behavior. **Do not cherry-pick or overwrite that state blindly.**
- Other existing branches: #79 visual polish; #83/#84/#85/#92 integration; #56/#57 Manage Plan; #47 Money Out. Do not rebuild these modules, merge their code into this documentation branch, or claim safe Money Out persistence.

## 2. Exact approved design-to-feature map

| Figma screen | Node | Intended app behavior / acceptance | Initial scope |
| --- | --- | --- | --- |
| 01 Journey / Your Saving Story | `1849:11298` | Show month activity **from owned persisted entries**, manual-log wording, accurate count, contextual badge link and recent activity. | Wave A |
| 02 Timeline / Three Saving Events | `1849:11322` | Monthly chronological ledger with real entries and eligible milestones; each row opens its correct available detail. | Wave A |
| 03 Achievements / What You Earned | `1849:11346` | Earned shelf, meaningful locked state, tap-to-detail; use approved native badge assets and stable badge IDs. | Wave A |
| 04 Quarter Way / Badge Details | `1849:11362` | Render only **actually earned** Quarter Way eligibility; show earned date only if verifiably stored or derived; calm on reopen. | Wave B |
| 05 Journey Empty / Goal No Entries | `1849:11380` | Existing owner-scoped goal at 0 recorded; do not invent XP, badges, streaks, or saving rows; working goal CTA. | Wave A |
| 06 Journey Empty / No Goals | `1849:11401` | Separate no-owned-goals state; CTA runs **existing** Create Goal flow; explain manual saving. | Wave A |
| 07 Journey / Money Taken Out | `1849:11420` | **Future reference only:** money-out ledger entry only after #42/#80 safe persisted event contract and availability gates. Do not simulate a withdrawal as real. | Blocked |
| 08 Journey / Completed Goal | `1849:11442` | Real completed lifecycle state; one-time contextual celebration on actual transition; calm return and history CTA. | Wave B |
| 09 Full Timeline / All Time | `1849:11457` | Real all-time filter and pagination/large-history behavior; stable chronological grouping, no invented entries. | Wave A |
| 10 First Step / Earned Badge Detail | `1849:11481` | Account-first legitimate recorded-save badge; keep earned on later plan edits; no duplicate unlocks or unsupported dates. | Wave B |
| 11 Completed Goal / Story Detail | `1849:11505` | Show the **actual** completed goal history and saved amounts; no static sample story shown as real activity. | Wave B |

Direct screen links: prepend `https://www.figma.com/design/tce3nRBcRwyObJMwQzA2rK/Gamification-Saving-SaaS?node-id=` and replace colon in node ID with a hyphen. Section 10 is the canonical source; archived sections and old all-in-one concepts are not approved for handoff.

## 3. Proposed engineering slices (do not implement until handoff approval)

### Wave A — Journey shell + truthful timeline and zero states

1. Audit/reuse `DashboardView.journeyPage`, `PipoMilestonesDCard`, `PipoActivityHistoryDCard`, existing app navigation and earned-badge sheet. Prefer small reusable SwiftUI views and a testable pure timeline projection over a second navigation stack.
2. Derive account-owned timeline items from actual persisted events with stable identifiers. Separate genuine contribution events and earned milestone events; never synthesize a transaction merely because progress crossed a threshold.
3. Add current-period and all-time filters grounded in user locale/calendar. Clarify sort determinism (timestamp + stable ID) and separate event-date from received/recorded-date if needed. Keep large logs accessible without truncating all-time to existing `prefix(12)`.
4. Implement approved no-goals and has-goal/no-entries states with existing Create Goal / Goal Detail actions, keyboard/safe-area and a no-guilt copy treatment.
5. Expose earned vs locked badge collection, with existing badge IDs and art. Detail navigation must not mutate achievements or XP.

### Wave B — badge detail + true completed-goal story

1. Only after Wave A QA: add Quarter Way / First Step badge detail and completed goal story. Use real persisted goal and award eligibility. **Do not hard-code the Figma example dates or rupiah amounts.**
2. **Data gap:** current displayed badge collection is based on stored badge IDs; do not assume a durable earned-at timestamp exists. If none exists, show "Earned" without invented date. A new migration/derived chronology is a separate evidence-backed review.
3. Trigger one-shot Pipo V4 celebration only on the original persisted qualifying event or real goal completion transition; no re-trigger on screen navigation, app restart or profile hydration. Provide Reduce Motion static fallback and no notification pressure.
4. Preserve lifecycle behavior for paused, archived and completed goals. Do not offer deposit controls when a lifecycle state disallows recording.

### Deferred entirely

- Design 07 Money Taken Out: **preview-only until signed-off ledger/atomic write + proper rollback, XP and reward reconciliation** (#42/#80). Do not gate the non-withdrawal Journey rollout on a hypothetical event.
- Group invitations/remote shared contribution claims and unverified banking data. Existing local group plan behavior is not proof of multi-account group ledger.
- Full historical backfill of badge award timestamps, new financial schema, push notification logic and monetization.

## 4. Non-negotiable data and trust contract

- **Per account:** no account A goal, history, badge, private widget snapshot or timeline event appears for account B, including after sign-out, sign-in, offline restore or app-switch.
- **Financial correctness:** use real self-reported savings only; Pipo neither holds nor verifies bank funds. Do not call manual entries "bank transactions" or "money moved".
- **Multi-currency:** format each event in its original ISO currency and exact minor units. **Never sum different currencies into one monthly total or cumulative amount.** For multi-currency timelines, show count plus per-currency subtotals or omit the single total until the product design approves the treatment. Do not silently convert or sum with ad hoc FX rates.
- **Immutability / rewards:** no duplicated XP, badge, milestone or completion event on retry, replay, sync conflict, app restart or rendering. A failed save gets no celebration. No fake timeline rows derived from unavailable backend events.
- **Historical continuity:** existing logs, balances, XP, unlocked badges, achievements, goal status and private asset ownership remain unchanged by visual/navigation changes.
- **Calendar and localization:** preserve source event time, locale/calendar period boundaries, DST/month end, very large values, LTR/RTL and currency precision. Confirm model semantics before selecting which date controls month grouping.
- **Accessibility:** VoiceOver actionable labels, correct order, Dynamic Type 320pt, at least 44pt controls, long goal/currency names, focus restoration and Reduce Motion; signed-device VoiceOver remains a separate release gate.

## 5. Test plan for first implementation PR

| Gate | Focused evidence |
| --- | --- |
| Required `Static & Harness QA` | Current exact-head static/harness checks pass. |
| Required `build-and-test` | Native iOS build, existing XCTest, no SwiftData/persistence regression. |
| Journey empty states | Synthetic owner: zero goals vs 1 goal/zero events; correct CTA and no fake awards. |
| Journey real history | 0, 1, 3, 13+ contributions; correct count/date/currency, filter, no hard-coded rows, no truncation. |
| Account isolation | Two users, account switch + offline restore; no private data leakage. |
| Achievement detail | Never-earned/earned/replayed history; badges and earned dates truthful; no duplicate reward. |
| Completion story | Real transition once, preserved history, no repeat animation on reopen. |
| Multi-currency | USD + IDR + another currency; no mixed-currency aggregate, exact minor units. |
| Safety regression | Money Out remains unavailable/review-only where not implemented; plan management, First Save and existing 320pt QA unchanged. |
| Visual proof | Simulator screenshot/MP4 from exact commit for all approved Wave A states; compare with Figma and inspect full-size readability. |
| Manual release gate | Device VoiceOver, real device, signed Auth/account and conflict review before release. |

**Run strategy:** Keep feature PR draft during implementation to avoid unnecessary macOS runs. Use inexpensive local/static checks first, one controlled native iOS QA batch for the final review-ready head, and require owner’s **single final merge approval**. No automatic production deployment or Supabase migration.

## 6. Integration and handoff readiness gates

- [x] Canonical Ihsan Space section and 11 screen IDs inventoried.
- [x] Baseline SwiftUI/achievement engine/tests inventoried at SHA above.
- [x] Existing feature/PR overlap and no-duplicate boundaries identified.
- [x] Fintech trust and multi-currency failure cases documented.
- [ ] PR #92 exact-head iOS QA completed and owner has decided merge / hold / supersede; **do not interpret "CI-green" as permission to deploy CAS SQL**.
- [ ] Recompare Journey/Dashboard code against the resulting latest `main` and update file pointers/delta map.
- [ ] Confirm actual award-date provenance and all-time data semantics; avoid schema changes unless explicitly approved.
- [ ] Obtain owner implementation handoff authorization, then create the **separate** Wave A feature branch/PR.
- [ ] Focused native QA + visual preview, then one final explicit merge approval.

**All of the above is a developer preparation artifact, not UI implementation approval.** Figma remains untouched.
