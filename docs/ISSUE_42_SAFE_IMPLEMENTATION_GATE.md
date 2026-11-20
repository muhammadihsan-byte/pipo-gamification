# Issue #42 — Plan Management / Money Out: safe foundation

## Branching and scope
This is a **stacked** branch based on `feat/pipo-p1-all-approved-cards` (PR #46), not `main`. The approved Money Out cards live on PR #46; do not merge this branch directly to main before #46 is integrated and tested.

## Implemented on this branch
- Pure `PlanFinancialPreview.revisedTarget`: validates target, periods and exact itemized budget equality; preserves preexisting recorded amount; rounds suggested contributions up.
- Pure `MoneyOutFinancialPreview.calculate`: validates positive amount and sufficient net savings, calculates keep-date and keep-amount choices independently, and computes the final remainder.
- XCTest acceptance cases A, B and D from issue #42; non-persisting, no XP mutation.

## Explicitly NOT production-ready
- No money-out button connected to persisted records; no withdrawal ledger, corrected-entry audit history or corrections UI.
- No user-entered plan changes are saved by the preview.
- No Supabase migration or live SQL mutation has been applied.
- No cross-device replay, offline sync retry/idempotency or concurrent-balance guarantee has been proven.
- No real-device VoiceOver, Reduce Motion, keyboard/large text or complete goal detail flow QA has been proven.

## Required backend design before enabling save
The deployed `saving_transactions` table stores `id, goal_id, user_id, amount, xp_earned, date, created_at` for positive saving contributions. Money out cannot be passed through the existing positive-only sync or it would falsify savings and achievements.

Implement an append-only account-scoped adjustment ledger or carefully versioned transaction event model with:
1. Immutable UUID event IDs (idempotent retries), event kind `money_out` / `correction`, amount, optional private note, timestamps, and correlation to the original event for corrections.
2. Mandatory composite `(goal_id,user_id)` reference into an owned personal goal, RLS with `auth.uid()=user_id`, ownership checks on SELECT/INSERT/UPDATE, no anonymous grants. Prefer append-only rights; do not allow clients to modify prior events.
3. An **atomic server-side operation** validating money-out amount against **current persisted net balance** under concurrency with explicit transaction locking / serializable balance enforcement. Local preview validation is insufficient.
4. A pure reducer that derives net amount from contributions and adjustments without XP for adjustment events, preserving historical XP and contribution streak history.
5. Account A/B tests, duplicate request tests, network retry/relaunch restore tests, stale/offline conflict tests, and schema migration validation before connecting confirmation.
6. Plan revisions preserve historical cadence; future-only changes, budget equality and stale version conflicts are checked server-side.

## Release / review gate
One controlled macOS iOS build + XCTest on the exact PR head; screenshots/MP4 for live flows only after actual integration. No merge, TestFlight, App Store submission, live migration, or production financial writes on this branch without explicit approval.
