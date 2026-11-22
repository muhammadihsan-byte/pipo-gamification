# Pipo Goal Lifecycle V1 — Local-first, account-scoped

**Development scope:** issue #21. No data migration in Supabase, no paid entitlement changes, no TestFlight. A goal remains a record of user-entered saving amounts, not a bank balance.

## States and rules

- **In progress (active)**: incomplete, not manually paused or archived. Eligible for recording a saving and becoming a focus goal.
- **Paused**: the user intentionally stops tracking this goal for now. The recorded amount, transactions, XP, title and target stay unchanged. No deposit CTA, schedule widget or new XP may be awarded. Resume returns it to In progress.
- **Archived**: hidden from active goals but available in the Saving Goals history. Does not delete records or free paid goal slots automatically. Resuming is supported while the target is unfinished.
- **Completed**: derived from real recorded progress when current amount meets or exceeds a valid positive target. Pipo cannot manually mark an under-target goal complete, nor reopen an already-completed goal. The actual recorded amount, including any overrun, remains visible while progress caps at 100%.

Allowed unfinished transitions: Active → Paused or Archived; Paused → Active or Archived; Archived → Active. Completed is terminal.

## Account isolation and migration

- Newly added optional SwiftData fields: `PersonalGoal.lifecycleRaw` and `PersonalGoal.isFocusPreferred`.
- Historical rows have nil for both: status defaults to Active, and no goal is force-pinned. Unknown values safely default to Active.
- The focus choice is persisted on the owned goal itself and only selected among **active, account-owned** goals. Switching accounts never exposes the previous account's focus. Deleting an owned goal removes its local focus metadata with the record.
- A paused/archived focused goal falls back to another active goal; if resumed without a new user focus selection, it can become focus again. Choosing a new focus clears all other preferences **within the current account only**.
- Current Supabase `saving_goals` upload does **not** include pause/archive/focus fields. These states persist across app relaunch **on the same device**, but do not yet sync across devices or restore after reinstall. Product UI and marketing must not promise otherwise.
- Older persisted SwiftData stores require real-device migration acceptance with a disposable test account before public release. Unit tests validate new schema defaults and reopen behavior, not installed-app upgrade from an old signed build.

## Saving and gamification protection

- Main dashboard, personal detail, external widget deep-link, confirmation sheet and GamificationManager all block saving if status is paused, archived or completed. The widget URL handler must use the same owner-aware `canRecordSaving` eligibility as the app, rather than treating `progress < 1` as proof the goal is active.
- Completing a goal remains automatic upon recording sufficient user-entered savings; the existing one-time badge engine still determines unlocks and celebrations.
- **Consistency caveat:** pausing does not retroactively forgive scheduled streak periods. The existing period-based streak logic is retained, and Pipo should not claim a magical freeze/grace policy without separately specifying and testing its rules.
- Group goals remain **device-local** and do not create actual network member invitations. Group pause/resume is a local UI operation.

## Acceptance and outstanding expansion

- [x] Persist user-selected focus locally and isolate it to user-owned goals
- [x] Paused, archived and completed states with truthful UI and no lost history
- [x] Record-a-saving guards at UI *and* the gamification mutation layer
- [x] Resume paused/archived goals and allow view of completed history
- [x] Unit tests for default state, invalid transitions, blocked rewards and reopening a local SwiftData store
- [x] Validate local disk-backed full-schema close/reopen/reopen persistence for paused, archived, resumed, completed and account-owned focus; preserve transaction history, badges and XP, quarantine ownerless rows (automated QA, **not** a signed migration proof)
- [x] Reject stale widget deposit URLs for paused, archived, completed, group and foreign-account goals before routing, including a resumed goal recovery check
- [ ] Validate a signed iOS upgrade from pre-V1 persisted SwiftData on physical device
- [ ] Decide and design explicit grace/freeze behavior before changing consistency rules
- [ ] Add remote sync/restoration of status/focus only with versioned DB schema and conflict semantics. Proposed contract: server-issued monotonic revision (or ETag) per owned goal, compare-and-swap updates, conflict response with explicit local/remote review, and the active account's exclusive focus choice enforced atomically. A sync request must not overwrite a newer pause/archive with an older active copy. Deployed `saving_goals` currently lacks these versioned fields; no production SQL/grants/RLS changes are authorized in this PR.
- [ ] Confirm keyboard, large text, accessibility, widget and small iPhone on signed device
- [ ] Confirm product policy for archive vs paid goal-slot entitlement before monetization

Merge into main only after exact-head iOS CI is green and final owner approval.
