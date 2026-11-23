# Pipo Flexible Saving V2 — Offline SwiftUI slice (2026-11-23)

**Canonical design:** https://www.figma.com/design/tce3nRBcRwyObJMwQzA2rK/Gamification-Saving-SaaS?node-id=1849-11104

**Design status:** Seven screens marked "UX APPROVED WITH BUTTON FIX", not a release approval. Existing Flexible Saving existed before this PR. The design's button-label color correction remains pending in Figma. SwiftUI uses the already-shipped **high-contrast** `PersonalPlanPrimaryStyle` rather than copying an uncorrected, absolute-positioned mockup.

**Developer status:** Source-only draft PR; macOS native build, screenshots, XCTest, VoiceOver and App Store QA intentionally deferred. Not suitable to merge yet.

## Figma → implementation mapping

| Approved frame | SwiftUI path and state | Boundaries |
| --- | --- | --- |
| 01 Choose Rhythm · `1849:11114` | `CreateGoalView.rhythmFields`: full-width five options, two-line copy, Flexible explanation, accessible selection, 44pt+ controls | No scheduled dates or streak; existing goal timeline retained separately |
| 02 Review Plan · `1849:11135` | `ReviewPlanView.flexibleReview`: account's typed target/currency/target date, four factual detail rows, Not scheduled, manual-money disclosure; sticky primary CTA | No automatic payments, no claimed bank balance, no invented flexible deposit |
| 03 Plan Ready · `1849:11162` | `ReviewPlanView.flexiblePlanReady`: real zero-recorded goal, bundled `PipoV4Joy`, optional first manual save or view goal; scroll-safe footer | Appears **only after** `modelContext.save()`; no XP on creation |
| 04 Returning Goal · `1849:11180` | `PersonalGoalDetailView.details`: factual fractional progress, owner-scoped history, gentle no-streak pace card, existing safe-area record action | No synthetic Rp1,425,000/23.75%; derives from actual goal |
| 05 Record Saving · `1849:11209` | `DashboardView.saveConfirmation`: existing manual sheet with Flexible copy and disclosure, post-persistence callback, safe-area CTA | Retains current currency, rollback on persistence error; no money movement |
| 06 Quarter Way · `1849:11239` | Reuses actual `AchievementEngine`, `PipoGoalProgressBCard` and `ConsistencyMilestoneView` (existing runtime, no new static reward mock) | 25% badge **only when truly earned**; no reward from changing rhythm |
| 07 Updated Goal Detail · `1849:11259` | Same owner-scoped real Goal Detail and Journal at new percentage, no penalty for Flexible saving | Actual 25% (or any real value) instead of Figma's illustrative number |

## QA contracts

- New native XCTest cases are authored but not executed: flexible goal fractional progress `23.75%`, one manual `75,000` contribution from `1,425,000` to `1,500,000` (25%), no streak; creation never grants rewards.
- Linux static-source guard: `scripts/test_flexible_v2_ui_contract.py` checks navigation, data semantics, copy and scroll-safe CTA.
- New source actions use existing `RootView` → `NavigationManager.requestDeposit` → `DashboardView` manual saving path. No extra transaction write at creation.
- User-account scoping is retained in `AccountScope` and `ownedHistory`. No schema, SQL, Purchase/StoreKit, entitlement, payout or payment changes.
- Always present goal date as a goal aspiration, *never* a required day to save; Flexible rhythm shows no missed period/streak/deadline pressure.
- Never copy Figma's example amounts, earned badges or photograph into actual user data. Existing asset `Pipo/Assets.xcassets/PipoV4Joy.imageset/Contents.json` was verified in `main`.

## Deferred gates before any merge

1. Signed design correction to button-label color in Figma and final visual parity approval; current native button foreground stays contrast-safe.
2. Re-enable Mac runner only with product-owner authorization. Native Swift compilation, two new XCTest regressions, full seven-screen screenshot/MP4 comparison against Figma, 320pt and 393pt widths, Dynamic Type, keyboard and sticky footer avoidance, Reduce Motion/VoiceOver.
3. Prove the optional Record first saving CTA does not lose the newly created goal during SwiftData query propagation; verify retry/failure leaves amounts untouched.
4. Continue independent Pipo #95 visual polish before integrated QA; do not infer PR readiness from Linux source checks.
5. No merge, production deployment, live database changes or TestFlight until one owner final approval.

## Next queue

After this draft PR, audit and slice genuinely missing approved Journey Wave B states, then Supporting Navigation; do not convert review-only Authentication, Notifications or Paywall mockups into release-ready features without approvals.
