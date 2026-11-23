# Pipo — Autonomous approved UI slicing register (Mac runner paused)

Updated: 2026-11-23. Scope: source-only SwiftUI slices and Linux checks.
Owner direction: advance from one approved area to the next without asking for
repeated continue instructions. **Do not merge, enable production flags,
deploy Supabase SQL, trigger paid macOS runners, or submit TestFlight.**
Every slice remains a reviewable draft PR until native screenshot/VoiceOver
coverage and one final owner approval are available.

## Source of truth and separate statuses

- Monitor: [Figma Ihsan Space](https://www.figma.com/design/tce3nRBcRwyObJMwQzA2rK/Gamification-Saving-SaaS?node-id=1847-10188)
- Design backlog: [Ihsan Space 19](https://www.figma.com/design/tce3nRBcRwyObJMwQzA2rK/Gamification-Saving-SaaS?node-id=2039-21120)
- Canonical handoff: [08 Developer Handoff](https://www.figma.com/design/tce3nRBcRwyObJMwQzA2rK/Gamification-Saving-SaaS?node-id=788-419), [#88](https://github.com/muhammadihsan-byte/pipo-gamification/issues/88)
- Source branch status, native test status, design approval and release status
  are independent, never automatically inferred from one another.

## Source-backed queue; reassess main and open PRs before each batch

| Area | Evidence | Offline action | Hold |
| --- | --- | --- | --- |
| #70 Spark period history | [Approved Spark semantic states](https://www.figma.com/design/tce3nRBcRwyObJMwQzA2rK/Gamification-Saving-SaaS?node-id=1616-27350), [issue #70](https://github.com/muhammadihsan-byte/pipo-gamification/issues/70) | In progress: read-only history on Goal Detail, owner scoped | Native visual/XCTest, no new badge grant |
| #71 Pipo V4 assets | [Approved pose/camera](https://www.figma.com/design/tce3nRBcRwyObJMwQzA2rK/Gamification-Saving-SaaS?node-id=1529-7055) | Inventory reusable approved assets, SwiftUI references, event-to-pose mapping | Rear/side rig excluded, animation QA later |
| #72 First Spark motion | [Approved 780ms benchmark](https://www.figma.com/design/tce3nRBcRwyObJMwQzA2rK/Gamification-Saving-SaaS?node-id=1606-19442) | Prepare event-safe trigger and Reduce Motion fallback | No native motion signoff without Mac |
| Flexible Saving V2 | [Seven approved frames](https://www.figma.com/design/tce3nRBcRwyObJMwQzA2rK/Gamification-Saving-SaaS?node-id=1849-11104) | Reconcile existing flexible flow, slice only missing UI | Figma button-label color fix pending; preserve Save rules |
| Journey Wave B | [11 approved Journey screens](https://www.figma.com/design/tce3nRBcRwyObJMwQzA2rK/Gamification-Saving-SaaS?node-id=1849-11284) | Nonfictional badge/detail and completion states after #95 | #95 unmerged; no fake earned-at or Money Out |
| Supporting Nav | [Five approved experiences](https://www.figma.com/design/tce3nRBcRwyObJMwQzA2rK/Gamification-Saving-SaaS?node-id=1850-8126) | Compare current navigation and add missing approved states | Safe-area audits, no early merge |
| Notifications / Widgets | [Notifications V1](https://www.figma.com/design/tce3nRBcRwyObJMwQzA2rK/Gamification-Saving-SaaS?node-id=1924-15633), [Widget V2](https://www.figma.com/design/tce3nRBcRwyObJMwQzA2rK/Gamification-Saving-SaaS?node-id=1935-17263) | Prepare view-only components for explicitly approved designs | Notification screens also marked REVIEW; widget rig QA pending; no live pushes |
| Authentication | [Three core approved, 18 review states #86](https://github.com/muhammadihsan-byte/pipo-gamification/issues/86) | Inventory and prepare core-only parity after canonical handoff | Provider configuration, signed auth QA |
| Paywall / group invitation | [#87](https://github.com/muhammadihsan-byte/pipo-gamification/issues/87), [#88](https://github.com/muhammadihsan-byte/pipo-gamification/issues/88) | Document blockers, never simulate live purchase/invitation | Source or UX approval missing |

## Current batch: #70 owner-scoped period history

- Adds period rows derived from existing SavingConsistency.periodIndex.
- Reads real, owned, non-duplicate, positive manual transactions; never
  aggregates across goals/accounts, never reads account-wide profile streak.
- Up to six scheduled windows, calendar-aware, with honest per-period counts.
  A current open window is never prematurely called missed.
- A return after a gap is shown compassionately without granting a badge.
- Flexible goals keep their existing no-pressure UX, with no scheduled cells.
- Goal Detail reuses safe-area-aware scrolling and its full Saving Journal.
- Three XCTest regressions are added but NOT executed without Mac runner.
- Ubuntu static-contract checks do not prove SwiftUI native compile or
  pixel-perfect visual parity.

## Continue rule

1. Recheck latest main, open PRs, exact approved Figma frames and issue.
2. Slice the next ready, unimplemented approved area on its own branch.
3. Open a draft PR targeting main (or explicitly stack a dependent PR).
   Keep paid Mac runner OFF, no merge or production activation.
4. Run Linux-only static/harness QA. Fix source/static failures as needed.
5. Publish status with native/design/backend blockers, then move to the next
   approved area without another user continue instruction.
6. Resume native XCTest, iPhone screenshots, VoiceOver, Dynamic Type, 320pt
   and 393pt parity only when user re-enables Mac runner. One final merge
   approval after integrated QA. Never silently bypass design review.
