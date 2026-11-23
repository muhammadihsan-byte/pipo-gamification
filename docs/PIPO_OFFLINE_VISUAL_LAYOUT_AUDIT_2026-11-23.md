# Pipo — Offline visual layout audit and contained follow-up (23 November 2026)

**Scope:** Full composed source of [Draft PR #100](https://github.com/muhammadihsan-byte/pipo-gamification/pull/100), revision `31bbea4d87ec16f6361b1e90e3d3161d5ff85ee4`. This work is a **source-level layout risk mitigation** prompted by the user's native iPhone screenshot. No native simulator/device run, screenshot confirmation, Figma mutation, macOS runner, merge or production change.

## Observations vs. confirmed failures

1. **Manage Plan — Finish Date and Target editors:** the user's previous QA contact sheet showed the lower disclosure and target/budget row partly obscured near the action footer. The old implementation used a `GeometryReader` with manually calculated `compactBottomReserve`, then a `VStack` containing a scroll view and a separately fixed-height footer; the explicit `.frame(width: geometry.size.width, height: geometry.size.height)` combined with extra bottom padding made correct safe-area placement fragile.
2. **Achievements / Next Milestone:** screenshot showed the next milestone teaser near the bottom viewport. **Below-the-fold scroll content alone is not evidence of overlapping**. The sheet previously had `LazyVStack` with uniform `.padding(20)`. The update aims for stable sizing and additional accessible scroll clearance. Whether the actual element was physically clipped must be demonstrated with simulator geometry.
3. Other related screens were audited **for the same source pattern**; the page state and data logic are intentionally untouched. Source parity is not proof of pixel-accurate rendering.

## Changes

| Area | Offline source correction | Native QA to perform later |
| --- | --- | --- |
| Manage Plan Target/Date/Rhythm/Impact | Migrate bottom CTA into the **scroll view's `.safeAreaInset(edge: .bottom)`**, remove `compactBottomReserve`, remove explicit geometry-sized outer frame, keep the entire unsaved/prototype notice within the scrolling content. Scroll can shrink as keyboard changes the safe area. | iPhone 320pt/393pt; keyboard present/hidden; date picker; target budget action completely above footer; safe area & swipe under Dynamic Type AX categories |
| Achievements collection / Next Milestone | Eager `VStack` sizing for bounded collection, `Text.fixedSize(... vertical: true)` for longer milestone copy, `padding(.bottom, 56)`, explicit scroll bounce behavior, constrained readable content width. | Confirm complete badge collection + all locked rows scroll above home indicator, next milestone not covered; screenshot full scroll including bottom, VoiceOver focus and scroll actions |
| Personal plan / Flexible Plan Ready | Existing `SavingPlanPage` and `flexiblePlanReady` safe-area footers retained. | Ensure CTA visible with large keyboard and dynamic content; no premature goal writes |
| Saving sheet and milestone celebration | Existing `.safeAreaInset` and scroll layout retained; no financial logic changed. | Confirm record-saving sheet, event celebration and footer hit targets across sizes |
| Goal Detail & Dashboard navigation | Existing source review confirms scroll + separately laid out nav/footer; no unverified geometry changes introduced. | Check Money Out action does not overlap saving footer (existing `tapButtonAboveSavingFooter`), goals journey scroll and tapped elements |

## Testing gates

- New `scripts/test_offline_layout_collision_guard.py`: five Linux source contracts detect the old manually reserved bottom frame, footnote relocation, Achievement lower scroll reserve and other shared safe-area patterns.
- Expanded existing `PipoUITests/PipoUIRecordingTests.swift` UI tests: targeted **layout geometry assertions** scroll target/budget row, date impact warning, and Achievements next-milestone into a rectangle fully above the pinned footer or scroll bottom. The helper checks exact `frame.minY/maxY` bounds; static labels are not required to report Button hit-testing capability. Screenshots remain attached on subsequent native QA.
- Existing Linux `swiftc -frontend -parse` integration scan and source contracts remain in place. **A green Linux test does not certify Apple's SwiftUI layout, Xcode type checking or screenshot quality.**
- Do not run macOS to check these until the product owner explicitly re-enables it. Once enabled, run the **combined exact head**, compare screenshot to approved Figma, and correct any discovered clip/hit-test regressions before final merge approval.

## Lifecycle / integration

This branch is layered on #100's complete #95–#99 feature combination, **not** a standalone patch on main. A subsequent combined candidate PR targeting main will include #100 plus this polish; **never merge both integrated PRs independently**. Keep original #95–#99 for source/provenance. All remain open/unmerged, no Supabase production SQL, Apple purchase/entitlement activation, or TestFlight. 

## Native QA checkpoint — 2026-11-23 (owner authorized, single batch)

**Execution:** [GitHub Actions run #45136246961](https://github.com/muhammadihsan-byte/pipo-gamification/actions/runs/45136246961), exact commit `246684c112f8f8cfcf2131b8773a387db9258728`, iPhone 16 / iOS 18.5 simulator, Xcode 16.4. The temporary one-shot PR label was removed after start and the labeled event workflow exception has been retired. **Do not infer a pass from the older source-only review.**

**Verified facts:**
- Xcode compiled the integrated source and executed **157 XCTest units: 155 passed, 2 failed**.
- Both failures are pre-existing *strong* real-image assertions in `PipoTests/SavingTimelineSnapshotTests.swift`, rather than a compiler error:
  - `testManagePlanV2OverviewAt393And320PointWidths` — `Manage-Plan-V2-B01-320pt clips the footer action at the bottom edge`.
  - `testManagePlanV2AccessibilityTextAt320And393KeepsFooterVisible` — `Manage-Plan-AX3-320pt clips the primary action under accessibility text`.
- Screenshots extracted in the workflow artifact `ios-validation-45136246961` (artifact ID `14800725750`) corroborate that at 320pt the CTA extends below the 760pt host viewport. At 393pt it is visible.
- Because base XCTest failed, the later **cross-screen interactive UI/MP4 step did not run**, so the screenshot evidence does not prove Achievements, target/date editors, or full navigation are fixed.
- Root cause indicated by the code/snapshots: applying `.safeAreaInset` to the **nested ScrollView** inside an unconstrained max-height `VStack` failed to ensure the footer stayed inside the compact fixed-size host. Adding arbitrary content padding or deleting the screenshot assertion would conceal the defect, not fix it.

**Isolated follow-up, after that QA run (not native-verified):**
- Replaced the nested-scroll `.safeAreaInset` with a direct *measured-height VStack footer*, 12pt bottom clearance, and an explicit `geometry.size.width/height` outer frame so the scroll viewport yields space to the footer at both regular and accessibility text sizes.
- Updated the Linux source guard to enforce the bounded layout, without changing the screenshot pixel assertion. Removed temporary one-shot label trigger, restoring the original manual-only native workflow. No backend or saving-state logic was touched.
- **Important:** these changes remain pending fresh native evidence. We did **not** trigger a second paid macOS run. After owner authorizes the follow-up batch, rerun the exact new head and check all 157 native unit tests then five UI visual tests plus MP4.

Current gate: **native visual QA FAIL on old commit; correction staged but NOT yet verified. PR remains Draft/unmerged.**

## Final successful native verification — 23 November 2026 (supersedes failed checkpoint)

**Acceptance source:** [GitHub Actions native iOS QA #45145482661](https://github.com/muhammadihsan-byte/pipo-gamification/actions/runs/45145482661), tested exact SwiftUI app/head SHA `87e0d1cf12a2c64d10c5cc60187b81dc872c37c2` on macOS 15 / Xcode 16.4 / iOS 18.5 simulator.

- **157/157 native XCTest passed; 5/5 focused UI XCTest passed**. These include Journey Wave A, all eleven approved card families, large-text accessibility, Manage Plan Flexible/Impact review, target and date editors, and Money Out review safeguards.
- Both 320pt native pixel/snapshot assertions that failed earlier **passed without modifying the assertion thresholds**. Measured `PIPO_320_FOOTER_UPDATE` bottom at **748pt** in a **760pt** host, a 12pt lower clearance. This includes large accessibility text and regular-size content; 393pt snapshots also passed.
- Screen recordings and screenshots were exported in [ios-validation-45145482661](https://github.com/muhammadihsan-byte/pipo-gamification/actions/runs/45145482661), artifact ID `14804997648`. The five UI test cases and MP4 export concluded successfully. Prior failing runs are historical regression evidence, not the current head status.
- Source identity: the subsequent [safety-only PR #102](https://github.com/muhammadihsan-byte/pipo-gamification/pull/102) changes only `.github/workflows/ios-build.yml` and the Linux guard file `scripts/test_offline_layout_collision_guard.py`; **no native SwiftUI, models, assets, or XCTest app behavior was changed** after the passing native run.
- #102 replaces the old #101 label-gated macOS trigger with explicit workflow dispatch, removes `pull_request:labeled`, and permanently disables legacy draft #83/#85 macOS label jobs. It remains a **Draft** candidate, retargeted to `main` to execute combined Linux validation. Do not merge #101 and #102 independently.

**Current release gate:** Native targeted regression QA **PASSED**; combined PR #102 Linux QA must pass for its final exact head. Full pixel-perfect Figma parity across all screens, the final Pipo V4 pose exports/motion rig, outstanding color and UX approvals, App Store/TestFlight signing, paid entitlements and production rollout are **not** established by these tests. Await owner's explicit final merge authorization.

## Owner final merge authorization — 23 November 2026

The product owner explicitly approved merging the unified PR #102 into `main`. This is a **merge authorization**, not authorization for production DB migrations, App Store/TestFlight publication, StoreKit billing activation, CAS cutover, or automatic release deployments. Respect all repository branch protection and required GitHub Actions checks; merge only when the required checks for the exact PR head have succeeded. No app code or SwiftUI behavior was changed for this approval record. Previous independent PRs #95–#101 are provenance only and must not be merged separately.
