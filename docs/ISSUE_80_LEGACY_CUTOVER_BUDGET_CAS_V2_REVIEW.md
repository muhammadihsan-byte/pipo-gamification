# Pipo #80 — Old-client cutover + atomic budget CAS V2

**Status:** REVIEW / DRAFT ONLY. Not a production migration, enabled Save path, TestFlight release, or authorization for Mac minutes. Integrated preparation: [Draft PR #83](https://github.com/muhammadihsan-byte/pipo-gamification/pull/83). Backend CAS V1 source: draft #81; dormant client source: draft #82.

## Proven incompatibility and what cannot be promised

The signed iOS app currently calls `SupabaseService.syncPersonalSavings`, which invokes `saving_goals.upsert(payloads, onConflict: "id")` BEFORE inserting contribution records. The deployed Supabase project grants authenticated goal UPDATE, with owner RLS but no `plan_revision`; therefore two same-account devices can last-write-wins.

The reviewed #81 CAS migration must REVOKE ordinary authenticated UPDATE. After that cutover, the OLD app's UPSERT fails (including for normal goal-first saving sync). Even if the client goal payload is identical, PostgREST's conflict-update operation still requires UPDATE privilege. **There is no server-only, zero-breakage solution that both preserves the old arbitrary UPSERT behavior and guarantees CAS protection.** A trigger that silently turns old UPDATE into a no-op would mislead the user into thinking a changed goal had been backed up; restoring direct UPDATE permission would reopen the CAS bypass. Neither is acceptable.

This branch includes a **real signed local Auth PostgREST probe** that asserts old UPSERT is rejected after the v2 cutover. That result is an expected security property, NOT proof that old apps have been upgraded or will provide a graceful error.

### Required signed-client compatibility rollout

| Phase | Server | New client | Old installed client | Release gate |
| --- | --- | --- | --- | --- |
| A — now | Existing owner RLS, direct goal UPDATE still granted | Continue review-only Manage Plan; separate local save from cloud confirmation; design new sync | Existing UPSERT works with known stale-write risk | No production SQL changes |
| B — bridge release | Still legacy schema (no revision RPC) | Ship signed INSERT-only goal creation, owner-scoped readback, stable UUID journals, cross-account and error UX. If CAS RPC unavailable, queue plan edits for later and never claim cloud Save | Continue old UPSERT during adoption window | Native iOS QA + signed release approved, old-version telemetry and rollback ready |
| C — controlled CAS cutover | Apply reviewed #42 then #29 then #81, followed by v2 budget schema/RPC in transactionally safe order. Revoke direct UPDATE + v1 mutation access | Use authenticated CAS V2 with full budget payload, replay UUID and current remote readback. Require explicit legacy-budget review | UPSERT denied. Older versions need to upgrade to restore cloud sync; no silent loss | Separate owner-approved maintenance/upgrade plan, staged signed tests, backups, integrity check |
| D — post-cutover | Monitor revision errors and rejected legacy upserts | Keep offline/pending drafts visible; conflict UX and recovery. No history/XP rewriting | User-facing forced update depends on client capabilities already shipped; truly old binaries may show generic sync error | Cohort adoption policy, help/upgrade communications, support/incident plan |
| E — rollback | Prefer keeping server safe/read-only and rolling forward a compatible fix | Reconcile original pending UUID and receipts | Old apps still cannot safely write until upgraded | Regranting UPDATE is an **explicit security downgrade**, NEVER automatic |

**Caveat:** The bridge release, signed version telemetry, minimum-version enforcement, and in-app update UX are NOT yet implemented. Server cannot ensure old binaries show a friendly upgrade screen if that code was never shipped in the binaries. The ship/no-ship decision needs real installed-version adoption evidence; currently unavailable.

## Atomic budget contract V2

The current `PersonalGoal.subItems` array is SwiftData-only. Each `SubItem` has UUID, trimmed title, amount, optional currency minor units and `isCompleted`. `PipoPlanV2Budget` maps these fields into editor draft; completion must not award XP or mutate saving history.

New **REVIEW-ONLY** `supabase/proposals/issue_80_budget_cas_v2_REVIEW_ONLY.sql`:

- Requires a disposable staging DB with #42 contribution guard, #29 append-only ACL, #81 CAS V1. It does **not** run in production and is never added to `supabase/migrations/`.
- Adds `budget_snapshot_state` on `public.saving_goals` (default `needs_review`). A BEFORE INSERT trigger forces `needs_review` even if a malicious/buggy client sends `synced` on CREATE. Existing goals begin `needs_review`, so an absent cloud breakdown is not assumed equivalent to an empty budget.
- Creates `private.pipo_plan_budget_items_v2` and `private.pipo_plan_budget_receipts_v2` with goal-owner FK, cascaded account deletion, row security, and NO table access for `anon` or `authenticated`. Not exposed to Data API.
- `public.pipo_read_plan_budget_v2(goalID)` is authenticated-only with explicit `auth.uid()` owner check and strict allowlisted snapshot. No direct budget-table read needed.
- `public.pipo_apply_plan_budget_v2(..., p_items jsonb, p_budget_import_confirmed bool)` locks the owner goal row, validates revision, **complete ordered budget list** and exact amounts, stores target/date/rhythm + all item rows atomically, then one immutable receipt keyed by owner + UUID. A request replay with identical UUID + data returns original receipt even after a later revision. Changed payload with same UUID is rejected. A stale revision returns a conflict, not a write.
- 0–64 budget rows are allowed. For nonempty budget, the sum MUST equal the full goal target (never just remaining savings). Each row has one distinct UUID, title 1–80 characters, positive amount in supported 0/2-decimal currency, completion bool, stable ordering. `[]` is an explicit empty budget (not omitted/unknown). Currency cannot change. Target and budget cannot be written separately.
- Initial `needs_review` requires `p_budget_import_confirmed=true`. **The app must actually show the local-vs-cloud budget review and get user confirmation**; a Boolean alone is not proof of consent. After adoption, the server marks `synced`; later V2 edits may use false when the existing snapshot was already synced.
- V2 revokes client execution of target-only `pipo_apply_plan_revision_v1` to prevent the target/budget becoming inconsistent. No direct authenticated UPDATE is restored. Historical savings, XP, achievements and money movement are untouched.

### Strict recovery contract for future app integration

1. Fetch *fresh, owner-scoped* plan + budget revision and `budget_snapshot_state`, checking authenticated user before and after awaits. Never infer cloud contents from an empty response or stale SwiftData cache.
2. If `needs_review`, show an explicit import/review page: original local items, target, changes, and consequences. If no local budget exists, user still explicitly acknowledges replacing the unknown cloud state with an empty allocation. No auto-import on login.
3. Build a canonical immutable request containing all rows, stable item UUIDs, expected revision and target. Stage a durable per-owner request BEFORE RPC. **Current V1 pending plan journal stores no budget; it MUST NOT be reused to send a V2 plan mutation.** Add a V2-specific journal or reviewed schema upgrade first.
4. RPC receipt `applied` is not final. Fetch a NEW remote owner-scoped budget snapshot and verify full ordered IDs, names, amounts, completion bits, currency, target/date/rhythm and server revision. Retry with original request UUID after a timeout, never a new one.
5. On conflict, keep original local draft and show latest remote snapshot; user chooses reapply, revise or discard. Reapply creates a NEW UUID only after explicit decision + latest revision.
6. After fresh verified readback, perform an audited SwiftData merge that **does not** replace local-only saving records, XP or achievements. Preserve independent allocation-completion flags; never treat them as money transfers. Only clear the durable local pending receipt after local consistency is proven. The currently dormant create-only reconciler does not yet perform this V2 budget merge.
7. On account switch/deletion, block foreign-owner intents. Add secure receipt retention/quarantine cleanup and verify offline history. Current journals have a fixed 100-entry limit and no compaction policy.

## QA and release gates

**Automated, disposable Linux:** `scripts/test_issue80_budget_cas_v2_client.py` compiles production Swift V2 request/receipt code using a synthetic currency shim; `supabase/local_qa/test_issue80_budget_cas_v2_STAGING_ONLY.sql` tests target/item atomicity, initial review, duplicate IDs, amount precision, changed replay, cross-account RLS, immutable history and rollback. `scripts/local_authenticated_issue80_budget_v2_qa.py` signs in real local Supabase Auth A/B users and exercises parallel PostgREST budget RPCs plus a realistic old-client UPSERT denial. All require Linux/loopback and are *not* a real production rollout.

**Outstanding before activation:** new signed bridge application, installed-version distribution and forced-update plan, V2 durable budget intent/reconciliation, signed Xcode build and native SwiftData QA, visual approval, non-disposable staging migration with backups/rollback, and separate explicit owner authorization for production SQL. **Passing Linux does not authorize merging or enabling Manage Plan Save.**

**Compatibility decision: BLOCKED until the old-app upgrade strategy is accepted.** That is an operational constraint, not a testing failure that can be ignored.
