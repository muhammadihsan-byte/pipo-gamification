## Scope
<!-- Describe what changes, impacted iOS/app areas, and any intentionally out-of-scope work. -->

## Figma → build traceability
- **Change type:** <!-- Design-driven / Bugfix / CI / Documentation / Security -->
- **Canonical Figma node URL:** <!-- Exact ?node-id= link, or N/A + reason -->
- **UX approval / version:** <!-- Explicit approved decision, or Pending / N/A. Never infer approval from a Figma page name alone. -->
- **GitHub issue:** <!-- e.g. Closes #x only when the ENTIRE issue is complete; otherwise Related #x -->
- **SwiftUI/code implementation mapping:** <!-- actual files / components / route and states -->
- **Design deviations and non-implemented explorations:** <!-- brief details or None -->

Refer to [Figma ↔ GitHub Build Sync V1](../docs/FIGMA_GITHUB_BUILD_SYNC_V1.md) and the [Figma handoff index](https://www.figma.com/design/tce3nRBcRwyObJMwQzA2rK/Gamification-Saving-SaaS?node-id=1667-1141). A Figma-approved source is not itself a merged build, and merge is not a release.

## Risk / data integrity
- [ ] Preserves ownership/isolation of goals, saving records, XP and achievements, or documents the approved migration
- [ ] Currency, rounding, money-out and manual-saving semantics checked where applicable
- [ ] Offline/error/retry/duplicate-action paths considered where applicable
- [ ] No new production database, money movement, payment, TestFlight or store deployment without separate approval
- [ ] N/A items explained below

**Impact / N/A explanation:**

## QA evidence (latest head only)
- **Tested head SHA:**
- **PR Fast Checks:** <!-- link + result -->
- **iOS Build and Test:** <!-- link + result, or explain why not applicable -->
- **Focused simulator / screenshot / MP4:** <!-- link, observed results or N/A -->
- **Accessibility:** <!-- VoiceOver, Dynamic Type, Reduce Motion, touch targets, keyboard -->
- **Remaining QA / release blockers:**

## Final review
- [ ] Design-to-code parity reviewed against canonical Figma source (if design-driven)
- [ ] No passing assertion is inferred from skipped, older-commit, or draft-only CI
- [ ] No exploratory/research-only Figma material silently promoted
- [ ] Issue/Figma status index update required at final merge handoff
- [ ] Awaiting explicit owner merge approval (a passing CI job alone is not approval)
