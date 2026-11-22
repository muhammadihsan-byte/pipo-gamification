# Issue #80 — Budget CAS V2 dormant journal + verified readback

**STATUS: REVIEW ONLY / NOT RELEASE READY.** Branch `feat/issue80-budget-v2-durable-journal-review`, based on integrated draft PR #83 at `0a85b592`. This change introduces no SQL migration, Supabase network call, enabled Manage Plan Save, Money Out action, TestFlight, or production behavior.

## Why this is separate from plan CAS V1

The original `SavingPlanCASIntentJournal` records only target, date, rhythm, and future contribution. It does not retain the complete budget row payload. Reusing it for `pipo_apply_plan_budget_v2` could produce a mismatched budget after crash, restart or retry. Budget V2 has its own per-authenticated-owner directory `Application Support/PipoPendingBudgetCASV2` and exact immutable payload.

## Dormant implementation

- `PendingSavingPlanBudgetV2Intent` records original goal UUID, request UUID, expected server revision, target and planned amounts in exact currency minor units, currency code, schedule, import-confirmation value, and **ordered** budget item UUID/title/amount/completion.
- Staging writes atomically before a future RPC. An identical request UUID and identical payload returns the original entry; changed-payload UUID reuse fails. A different request for the same unresolved goal fails. Account A's journal is not read from account B's file.
- Reopen decodes disk state as untrusted input and reconstructs an independently validated `SavingPlanBudgetV2Request`. Tampered amounts, invalid precision, wrong-owner records, duplicate item UUIDs, changed order or inconsistent state fail closed; never drop the queue on parsing error.
- `SavingPlanBudgetV2ReceiptValidator` must accept the exact applied or conflict response before transition. Applied becomes `acknowledged`, **not complete**. A stale response becomes `conflicted` and requires a conscious user decision.
- Only a **fresh, authenticated, owner-RLS-protected** `pipo_read_plan_budget_v2` response can be passed to the `SavingPlanBudgetV2SnapshotVerifier`. The client must check the Auth identity before and after the await. It verifies the entire budget list, target/date/rhythm, current revision and `synced` state before marking `verified`.
- `verified` remains on disk after relaunch and is not removed. It is **not** equivalent to applying SwiftData changes; a separate, audited local reconciliation commit and protected receipt-retention policy must be built before integration. There is intentionally no `finish` action in this review branch.
- Explicitly discarded stale conflicts retain a tombstone to prevent duplicate request UUID reuse. The 100-item limit fails closed rather than silently evicting receipts. Final compaction and account deletion are still missing.

## Test evidence and scope

`scripts/test_issue80_budget_v2_journal.py` compiles actual production Swift Foundation contract and exercises it with a temporary local directory on Ubuntu. Cases include: durable restart, exact replay, altered replay, second pending edit rejection, owner switch, invalid server receipt, current budget mismatch, mismatched revision, reordered items, verified restart, stale conflict requiring explicit discard, tombstones and corrupt JSON. Workflow is `.github/workflows/pr-fast-checks.yml`.

This is NOT an iOS Simulator, signed PostgREST adapter, production migration, two-device client sync or release proof. Existing PR #83 native and local Supabase proof remains separate, on different SHAs.

## P0 release gates remaining

1. **Legacy signed app bridge:** the currently installed iOS app still calls direct `saving_goals.upsert(onConflict: "id")`. Secure CAS V2 rollout revokes UPDATE and breaks that path. Ship and validate a **compatible signed bridge** while old schema remains active; gather installed-version distribution and define user upgrade policy. Never restore UPDATE as a silent workaround.
2. Authenticated client RPC + owner-scoped current budget fetch; run signed A/B tests against disposable backend. No service-role key in app.
3. Audited SwiftData budget reconcile and local ledger invariants; no XP, transactions, saving balances or badges changed by plan edits. Integrate account-deletion cleanup and policy for 100-entry journals.
4. Design/approve explicit legacy-budget import review, differences/reapply/discard conflict UI and truthful pending/offline feedback.
5. Native Xcode build, SwiftData relaunch/account-switch tests, full UI QA including IDR/USD/JPY; stage database migration ordering/rollback after a signed client upgrade.
6. Final owner approval **for merging**; another **separate** owner approval **before any production SQL or Release rollout**.

## Safety and rollout

`SavingPlanBudgetV2IntentJournal` is deliberately not called from the production app. `Manage Plan Save` and `Money Out` remain review-only. These types do not make HTTP calls or affect SwiftData. Existing PRs #79, #81, #82, #83 and main remain unchanged by this branch.
