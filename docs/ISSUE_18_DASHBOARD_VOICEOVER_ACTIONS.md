# Issue #18 — Dashboard B VoiceOver goal actions (focused slice)

## Problem and safe scope

Goal rows in Dashboard B used a long-press `contextMenu` for pause/resume/archive/focus. A VoiceOver user may not discover those controls. This patch preserves the visual design and existing ownership/transition guards while adding equivalent, accessible custom actions to the goal row.

- A compact goal announces its actual title, personal/group status, lifecycle state, manually recorded balance and percentage in one label.
- Custom accessibility actions mirror **only** the operations already shown in the existing context menu. No new saving mutations or backend effects.
- Closed/completed goals do not gain a resume or deposit action. Paused/archived goals expose the existing resume action.
- The row's ordinary tap still opens the existing detail route; its `pipo.dashboard.goal.<UUID>` test identifier remains unchanged.
- The existing dynamic SwiftUI text layout, card system, colors and Pipo artwork remain unchanged.

## Verification

- New dedicated Debug-only simulator test: `testDashboardGoalRowsHaveAccountSafeAccessibilitySummary` (uses local account-owned goal fixtures; no network/real credentials).
- Existing iOS build/unit/UI workflows run on PR head; inspect exact-head CI before merge.
- Manual physical VoiceOver rotor audit, smaller iPhone, Dynamic Type and mixed-goal screenshots are **still required** for full issue #18 completion.

## Release and roadmap gate

This is **only a partial accessibility slice** of issue #18. Leave the parent issue open even if this PR merges. Do not claim #18's no-goals/completed-only/past-due state matrix is fully validated.
No production data migration, financial writes, Supabase modification, TestFlight, or App Store deployment.
