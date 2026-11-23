# Pipo — Offline iOS UI integration of PR #95–#99

**Prepared:** 2026-11-23 · **Branch:** `integration/pipo-offline-ui-95-99-20261123` · **Target:** `main` · **Status:** Draft / source only / **HOLD for owner and macOS QA**.

## Why this branch exists
Four already-authored offline UI slices share files with the previously implemented Journey Wave A. Each individual PR is green on its own branch but independent source checks do **not** prove their combination. This branch composes exact changes from the five pinned commits without merging or modifying original branches:

- [#95 Journey Wave A](https://github.com/muhammadihsan-byte/pipo-gamification/pull/95) `c38d660b7c74ca9e5dc717f9e8e29eda9173a673` — base source, native QA passed **before integration** but owner flagged visual defects.
- [#96 Spark Period History](https://github.com/muhammadihsan-byte/pipo-gamification/pull/96) `9a720b586e5f709c19dd0ba5b0908258a85b48c5`.
- [#97 V4 Pose Registry](https://github.com/muhammadihsan-byte/pipo-gamification/pull/97) `e90646fdd41a329673be413dc2a0d714d7cf632d`.
- [#98 First Spark](https://github.com/muhammadihsan-byte/pipo-gamification/pull/98) `b4c7b55b6663dc4e85929b470dd30608ccb6f687`.
- [#99 Flexible Saving V2](https://github.com/muhammadihsan-byte/pipo-gamification/pull/99) `7540150d21f0ff17ad129905a23a426861157fac`.

**Integration mechanism:** start from #95 exact commit, apply exact file hunks from #96, #97, #98 and #99 with context checks; manually reconcile only the overlapping test insertion, workflow guard registration, and new-goal → saving-sheet navigation sequence. No force updates, cherry-picking unrelated work or runtime data migration.

## File overlap and resolution

| File | Competing PRs | Decision |
| --- | --- | --- |
| `Pipo/Features/Dashboard/ContentView.swift` | #95, #98, #99 | Keep Journey Wave A real owner history, post-persistence First Spark and Flexible manual-saving + late-query retry. One dashboard, one save callback. |
| `Pipo/App/RootView.swift` | #98, #99 | Keep one-shot milestone callback and optional first-saving route. **Integration-only fix:** navigate `popToRoot()` before `requestDeposit(goalID:)` so Dashboard owns the sheet; retain owner auth guard and deferred SwiftData query recovery. |
| `Pipo/Features/PersonalSaving/ReviewPlanView.swift` | #96, #99 | Keep scheduled goals' period history and Flexible goal's truthful no-streak pace, fractional progress, earned badge, manual history, optional first saving, safe-area CTA. Preserve other goal management options. |
| `PipoTests/GamificationManagerTests.swift` | #95, #96, #98 | Preserve all three XCTest suites; insert unique tests for #98 alongside #96 instead of replacing the conflicting insertion anchor. |
| `.github/workflows/pr-fast-checks.yml` | #95, #96, #98, #99 | Keep #95 source accessibility guard and all three new Linux-only guards, plus a cross-branch composition guard. |
| `Pipo/Core/DesignSystem/PipoMascotView.swift` | #97 | Keep approved source-pose registry; only available bundle stills can render. |
| `Pipo/Features/Gamification/ConsistencyMilestoneView.swift` | #98 | Keep Reduce Motion and one-shot 780ms **placeholder scene**, scroll-safe milestone CTA; this is not a full pose-accurate native motion proof. |
| Others | Single PRs | Retained unchanged from their respective exact-head source. |

## Integration assertions

- `scripts/test_offline_ui_integration_95_99.py` checks that Wave A, Spark history, V4 registry, First Spark and Flexible V2 all coexist; it fails on missing/duplicate tests, lost Linux checks, goal-first-saving route ordering, unsafe account scoping, post-save milestone sequencing and missing safe-area/Reduce Motion contracts.
- Existing individual source guards and test source continue to live in one combined tree.
- First Spark eligibility is a **presentation gate after successful manual saving persistence**; it cannot create XP, funds or badges. Flexible goals have no required saving dates and must not display streak pressure.
- Never fake cash, earned dates, withdrawals, bank confirmation, cross-currency totals or group member contribution events. Existing account isolation and manual-log copy stay intact.
- The Flexible plan-ready button must return to Dashboard and open its **existing manual save sheet**, not silently create a saving event or navigate behind the unclosed creation view.
- Static source checks alone cannot establish actual Swift compilation, touch hit testing, keyboard overlap or pixel-level visual correctness.

## Known holds (NOT fixed by source integration)

1. Owner-reported screenshots show potential clipped/covered text in Manage Plan target/date footers and Achievements next milestone. The previous four passing native UI tests were *functional*, not a full visual regression gate. Do not treat source-level safe-area assertions as rendered-proof.
2. #95 Journey Wave A itself remains **visual hold**, notwithstanding prior native XCTest. Wave B badge details, completion stories and Money Out ledger are separate design/data gates.
3. Source V4 pose identifiers do not provide the missing approved source PNG exports for near-hoof/hug; the #98 780ms movement remains intentionally incomplete.
4. Flexible V2 Figma button-label color correction remains an approval item. Rendered cross-device accessibility, dynamic text, input keyboard + modal stack, RTL and VoiceOver not proved.
5. Purchase verification, paid entitlements, CAS rollout, signed Apple developer/testing and group remote invitations remain blocked; this branch activates none of them.

## Before any merge (requires explicit owner approval)

- Re-enable Mac runner **only on owner's instruction**, then compile the **combined exact head**, run existing XCTest plus #70/#72/Flexible tests and native UI full flow, two-user account switch, app relaunch and saving persistence.
- Capture and inspect complete screenshots and simulator MP4 for Journey, Goal Detail, Manage Plan, plan-ready, first saving, Achievements at 320pt/393pt and Dynamic Type; compare with approved Figma without cropping any footer/CTA or milestone.
- Do real VoiceOver and device-level follow-up. Address owner-observed visual collisions across all reused components before final merge signoff.
- Keep original PRs #95–#99 and this integration PR **open/unmerged** during offline slicing. No production changes, no Mac runner, no release automation or TestFlight.

**In-source integration checks = offline-readiness only, not release candidacy.**
