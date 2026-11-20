# Pipo #44 — Remaining 11 Approved Card Families / Single Approval Handoff

**Scope**: implement selected Figma directions only, after [Budget Breakdown B Phase 1 PR #45](https://github.com/muhammadihsan-byte/pipo-gamification/pull/45). One branch, one final user approval before merging. Exact implementation source: [Pipo Card Implementation Map](https://www.figma.com/design/tce3nRBcRwyObJMwQzA2rK/Gamification-Saving-SaaS?node-id=1241-8629), [selected sets](https://www.figma.com/design/tce3nRBcRwyObJMwQzA2rK/Gamification-Saving-SaaS?node-id=1276-10198).

| Selection | Native view | Live usage | Real-data rule |
| --- | --- | --- | --- |
| 01 Goal Focus **B** | `PipoGoalFocusBCard` | Personal Goal Detail | User goal title, category, goalPhoto if actually present, single computed progress rail. Never the Bali example photo |
| 02 Goal Progress **B** | `PipoGoalProgressBCard` | Goal Detail, only if persisted Quarter Way badge is earned | Compact earned banner with approved actual badge asset; no second progress rail. Award is account-wide, so do not attribute to an unverified specific goal |
| 05 Milestones **D** | `PipoMilestonesDCard` | Journey | Approved First Step / Quarter Way art; earned/locked sourced from UserProfile, collection button works |
| 06 Inspiration **C** | `PipoInspirationCCard` | Goal Detail | Real local user photo if present, else explicit photo-free state; no invented user note |
| 07 Plan Overview **B** | `PipoPlanOverviewBCard` | Group Goal sheet; personal semantics supported by component | Recorded amount and target only; prepared group names are **not invitations or live members** |
| 09 Saving Decisions **D** | `PipoSavingDecisionsDCard` | DEBUG-only QA gallery | Both routes actually selectable for a **draft preview**. **Not** exposed as a persisted plan modification before #42 |
| 10 Input & Editing **D** | `PipoInputEditingDCard` | DEBUG-only QA gallery | Amount and optional note are editable and validated against a supplied recorded amount; **no bank withdrawal or saving-history mutation** |
| 11 Financial Impact **D** | `PipoFinancialImpactDCard` | DEBUG-only QA gallery | Pure before/after arithmetic, rejects negative/overdrawn/invalid amounts, never removes earned XP; no committed money-out event before #42 |
| 12 Activity/History **D** | `PipoActivityHistoryDCard` | Journey and Goal Detail | **Actual account-scoped SavingTransaction only**; no fictitious money-out or corrected entries |
| 13 Completed Goal **B** | `PipoCompletionBCard` | Home completed goals and completed Personal Goal Detail | Condition is derived from actual target; Pipo V4 Joy existing approved asset, journey action opens real recorded activity |
| 13E Empty State **B** | `PipoEmptyStateBCard` | Home when no goals | Existing approved V4 neutral image crop, real create-goal CTA, no fabricated savings |

## Design and engineering standards

- Reuses **TicketCard** as the single existing card surface, with additional explicit selected blush and mist variants. No parallel card container system or copied archived direction.
- Approved Pipo V4 images use existing app assets `PipoV4Neutral`, `PipoV4Joy` and `PipoBadge_*`; never substitute older mascot versions.
- Uses Pipo semantic card text color `PipoTheme.cardAccentReadable` (#D4315B, approx 4.78:1 on white) when Figma #E54569 fails small-text contrast; visual hierarchy, hierarchy spacing and app-wide #FF6584 progress accent remain.
- Touch actions are at least 44pt; scroll content expands for Dynamic Type; carousel and constant mascot movement are not introduced; V4 crop is a still, respecting Reduce Motion.
- **Goal Detail renders exactly one progress rail** (Goal Focus B); Progress B is an earned-only badge. Group Goal sheet has its own single progress rail.
- No Supabase schema, server, StoreKit, privacy, sign-in, saving engine, account owner metadata, rewards or production app deployment changed by this visual task.
- iOS DEBUG flag `-pipo-dashboard-qa -pipo-allcards-qa` uses in-memory seeded goals and badges; a sample completed goal exists only as a transient preview. QA gallery is unreachable from a release build.
- No network group syncing; no live shareable member invite state; no automated financial transfers. Calls to `money(...)` format self-reported values, not financial institution balances.

## Required functionality gates

**Full money-out behavior is a separate issue #42 / #16 acceptance requirement.** Do not interpret presence of three compiled preview components as a working withdrawal feature. Making them production navigable requires an account-scoped, tested edit/withdrawal ledger, idempotent saves, proper edit/correction operations, genuine schedule replanning, old-journal migration, proper offline conflict handling and no retroactive XP deletion. No fake "Saved" success is shown by the QA gallery.

## Controlled validation

- [ ] iOS build, existing unit suite and focused new unit tests for pure before/after preview, invalid inputs, no XP mutations and real completion state
- [ ] One DEBUG-only simulator UI gallery walkthrough documenting all 11 selections and the enabled route selection, with screenshots in exported workflow artifacts
- [ ] Check existing returning Dashboard, first-time onboarding, Budget Breakdown B / card #08 after this change
- [ ] QA at regular and smaller iPhone sizes; Dynamic Type and VoiceOver checks to be validated on a real device before public release
- [ ] Final code review and **one explicit user approval to merge**. Do not merge before approval
- [ ] Future native account-owned money-out editing/recovery #42, plus real Apple-signed device QA and exact image geometry are separately required before launch.

**Definition of completion for this PR:** 11 selected reusable card views built, eight driven by shipped account-owned app states, three draft-only designs validated in DEBUG QA but safely gated from production due #42. The user sees this honest division before the single merge request.
