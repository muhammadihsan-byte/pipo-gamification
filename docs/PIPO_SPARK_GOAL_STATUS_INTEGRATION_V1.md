# Pipo #69 — Per-goal Spark integration and QA

Reference: [Approved Figma active goal, consistent detail, and flexible states](https://www.figma.com/design/tce3nRBcRwyObJMwQzA2rK/Gamification-Saving-SaaS?node-id=1501-3885). Native asset registry: [Issue #68](https://github.com/muhammadihsan-byte/pipo-gamification/issues/68).

The new `PipoSparkGoalStatus.presentation` is an **account-owned projection** based on actual SwiftData `SavingTransaction` events scoped to one `PersonalGoal`. It uses existing `SavingConsistency.periodIndex` and `consecutivePeriods` from #14, including one event at most per scheduled period. The global `UserProfile.streakDays` is **never used** for Spark or a second goal.

**Semantics**
- Active scheduled saving in current period: show active count in correct day/week/biweekly period/month units.
- Last contribution in immediately previous period, with current period still open: show pending status and preserve previous streak count, with no premature missed-period language.
- One or more full scheduled periods missed: neutral ended streak state, with historical count retained for VoiceOver.
- New recorded contribution after a missed period: recovery, current new streak of **one** scheduled period. No reward is granted by the chip.
- First unsaved goal: notStarted; flexible: **Saving at your pace**, never overdue, ended, missed, streak pressure or deadline; paused/archived/completed/group: no active streak chip.
- Ignore future entries, foreign account/other goal events and legacy invalid pre-start dates. Ambiguous duplicate transaction UUIDs fail closed rather than fabricating a streak. Time-based status refresh uses SwiftUI TimelineView.
- Home Focus Card: keep existing title, manual-progress, next planned info, CTA and disclosure; add compact Spark **after the CTA**; other active personal goals receive their own small independent chip.
- Goal Detail: keep the one existing saving progress rail and approved #44 card family; insert compact **Your Saving Rhythm** summary, with text and an explicit spoken status. Primary Record button remains visible independently; changing rhythm reprojects without mutating prior history.

**QA**
- Four new pure XCTest cases: four unique weekly periods + same-period extra + second account and second goal; pending vs ended; eligible recovery only after a saved event; flexible, paused, future, duplicate UUID fail-closed.
- Existing #68 asset/accessibility tests remain in force. Run CI exact HEAD Xcode XCTest, visual screenshot on Home and Detail, long titles, Dynamic Type and real-device VoiceOver separately before release.
- No XP, badge, currency, money movement, Supabase schema, or database mutations. No deploy/TestFlight/merge until final owner approval.
