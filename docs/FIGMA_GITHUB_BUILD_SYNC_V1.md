# Pipo Figma ↔ GitHub — Design-to-Build Sync V1

**Last verified:** 2026-11-22 · GitHub `main` at `e656ca3813172e00e960cde132d6eb52a16b6006`  
**Mode:** Handoff and review-time status reconciliation. **Not** automatic Figma-canvas synchronization.  
**Owner tracking:** [Issue #63](https://github.com/muhammadihsan-byte/pipo-gamification/issues/63)  
**Figma sync board:** [08 Developer Handoff / Build Sync](https://www.figma.com/design/tce3nRBcRwyObJMwQzA2rK/Gamification-Saving-SaaS?node-id=1667-1141)  
**Figma source:** [Pipo UI/UX file](https://www.figma.com/design/tce3nRBcRwyObJMwQzA2rK/Gamification-Saving-SaaS)

## Source of truth and permissions

- **Figma** owns UX decisions, approval, canonical editable source screens and Pipo V4 motion direction. `01 Product Flows`, `02 Design System`, `03 iOS — Approved`, `05 Mascot & Motion`, `08 Developer Handoff`, and `11 Design Lab` are not interchangeable.
- **GitHub** owns actual SwiftUI source, PR state, merged commit, Actions results and simulator test artifacts.
- **GitHub Project** owns issue execution status, but its automation is independent of the Figma source; an issue may remain open after a partial feature PR is merged.
- **Release** is separate from all of the above. A merged PR or green Xcode simulator job is **not** evidence of TestFlight or App Store release.

## Status interpretation

| Status | Evidence required |
| --- | --- |
| Exploration | Named Figma lab or WIP section; not approved for implementation |
| UX Approved | Explicit owner approval + canonical Figma node ID |
| In Build | Implementing branch/PR + Figma source node + scoped acceptance and QA plan |
| Merged to main | PR reports `merged=true`; record the merged commit |
| QA Verified (scoped) | Passing exact-head build/test run, required focused simulator checks and artifacts, with residual risks listed |
| Released | Independently verified build distribution / store deployment, never inferred from merge |

A feature may have **UX Approved + Merged** and still require **device accessibility, backend/security, persistence, or release-wide QA**. Do not collapse those columns into one `Done` label.

## Baseline map — audit snapshot, not a live deployment feed

| Feature | Figma anchor | GitHub anchor | Build assessment |
| --- | --- | --- | --- |
| Dashboard B | [Dashboard direction](https://www.figma.com/design/tce3nRBcRwyObJMwQzA2rK/Gamification-Saving-SaaS?node-id=919-1154) | [PR #12](https://github.com/muhammadihsan-byte/pipo-gamification/pull/12), [issue #18](https://github.com/muhammadihsan-byte/pipo-gamification/issues/18) | PR merged; continued accessibility and edge-state QA |
| Approved Card System | [12-card handoff](https://www.figma.com/design/tce3nRBcRwyObJMwQzA2rK/Gamification-Saving-SaaS?node-id=1241-8629) | [PR #45](https://github.com/muhammadihsan-byte/pipo-gamification/pull/45), [PR #46](https://github.com/muhammadihsan-byte/pipo-gamification/pull/46), [issue #44](https://github.com/muhammadihsan-byte/pipo-gamification/issues/44) | Delivery merged; parity/closure checks separate |
| Goal Photo Hero V1 | [Goal image](https://www.figma.com/design/tce3nRBcRwyObJMwQzA2rK/Gamification-Saving-SaaS?node-id=1022-1194) | [PR #49](https://github.com/muhammadihsan-byte/pipo-gamification/pull/49), [issue #48](https://github.com/muhammadihsan-byte/pipo-gamification/issues/48) | Single-photo feature merged, multi-photo a later scope |
| Manage Plan V2 | [Approved V2 design](https://www.figma.com/design/tce3nRBcRwyObJMwQzA2rK/Gamification-Saving-SaaS?node-id=1459-3369) · [handoff](https://www.figma.com/design/tce3nRBcRwyObJMwQzA2rK/Gamification-Saving-SaaS?node-id=1626-1652) | [Draft PR #57](https://github.com/muhammadihsan-byte/pipo-gamification/pull/57), [cumulative PR #58](https://github.com/muhammadihsan-byte/pipo-gamification/pull/58) | PR #57 remains draft; #58 merged cumulative changes; reconcile before closing old draft |
| Global Experience V1 + currencies | [Approved source](https://www.figma.com/design/tce3nRBcRwyObJMwQzA2rK/Gamification-Saving-SaaS?node-id=1616-26728) · [handoff](https://www.figma.com/design/tce3nRBcRwyObJMwQzA2rK/Gamification-Saving-SaaS?node-id=1626-1653) | [PR #58](https://github.com/muhammadihsan-byte/pipo-gamification/pull/58) | Merged to main; release/regression QA separate |
| First Save Activation V1 | [Approved 8 screens](https://www.figma.com/design/tce3nRBcRwyObJMwQzA2rK/Gamification-Saving-SaaS?node-id=958-2239) | [PR #62](https://github.com/muhammadihsan-byte/pipo-gamification/pull/62), [passing iOS run](https://github.com/muhammadihsan-byte/pipo-gamification/actions/runs/44982576064) | Merged; exact-head iOS and first-save focused simulator passed |
| Flexible Saving V2 | [Design Lab section](https://www.figma.com/design/tce3nRBcRwyObJMwQzA2rK/Gamification-Saving-SaaS?node-id=1616-43697) | [Research issue #55](https://github.com/muhammadihsan-byte/pipo-gamification/issues/55) | Exploration: not yet approved, no production PR |
| Pipo V4 performance kit | [Acting & expression sources](https://www.figma.com/design/tce3nRBcRwyObJMwQzA2rK/Gamification-Saving-SaaS?node-id=1616-32312) | Feature-specific implementation only | Do not treat all WIP poses or storyboards as approved app assets |

### Latest baseline QA evidence

The [last merged First Save Activation change](https://github.com/muhammadihsan-byte/pipo-gamification/pull/62) passed [PR Fast Checks](https://github.com/muhammadihsan-byte/pipo-gamification/actions/runs/44982576056) and [iOS Build and Test](https://github.com/muhammadihsan-byte/pipo-gamification/actions/runs/44982576064) on head `b2b09558d7a2be0ec51d0a4e98a398f8d9c31f18`. Reported coverage: 125 unit tests and a focused first-save simulator journey. It does **not** attest all screen/device paths or release readiness.

## Required development PR handoff

Every new design-driven PR should contain:

1. **Canonical Figma:** exact page/section/node URL (never just the file root), approval date, source status and relevant comments.
2. **Scope:** affected SwiftUI components, states, entry points and known omissions. Do not silently pull Design Lab concepts into production.
3. **Parity:** exact interactions, copy, motion/reduced-motion, 44pt hit regions, Dynamic Type, VoiceOver, keyboard, empty/loading/error/offline states.
4. **Data:** manual saving is self-reported, never bank-verified or moved by Pipo. State account isolation, achievement eligibility, locale/currency, transaction correctness and persistence impact.
5. **Evidence:** exact PR head SHA, mandatory fast/iOS checks, relevant focused simulator paths, screenshots/MP4, explicit exceptions and final owner's merge approval.
6. **Handoff updates:** after merge, update Issue #63 and the Figma `08 Developer Handoff` index. Never alter canonical source frames merely to reflect a build status.

Read [CI QA workflow](./CI_QA_WORKFLOW_V1.md) for draft-vs-ready CI, targeted dispatch modes and latest-head check policy.

## Current known coordination blocker

[Pipo Roadmap Status Sync failed](https://github.com/muhammadihsan-byte/pipo-gamification/actions/runs/44980921433) with `Bad credentials` in the existing GitHub Projects GraphQL step, while PR Fast Checks and iOS build are separate checks. Fix or rotate the `PIPO_PROJECTS_TOKEN` **inside GitHub Actions secrets** with sufficient Projects permission; never paste a token in a ticket, PR, Figma, or chat. Re-run and verify workflow after the authorized owner updates it. Do not mislabel a Projects failure as an iOS compilation failure.

## Automation boundary

This V1 introduces **traceable links + PR authoring rules**, not two-way live sync. GitHub Actions currently cannot update editable Figma source nodes with the available configured workflow and no Figma write credential is installed for that purpose. Add automated status polling only as a separate reviewed design-ops feature with scoped credentials, non-destructive output, audit logs and clear conflict handling.

**Release policy:** No merge, App Store/TestFlight submission, production Supabase migration, or financial data edit is authorized by this documentation.
