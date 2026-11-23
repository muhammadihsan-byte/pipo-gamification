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
