# Issue #80 — Create-Only Goal + Verified Cloud Readback (dormant)

STATUS: REVIEW ONLY. No production backend changes, live CREATE/SELECT calls, Mac runner, or merge. Works with draft PR #82. Backend revision and CAS SQL proposal is separately reviewed under draft PR #81.

## First goal creation contract (future, currently UNWIRED)

1. Require current verified Supabase Auth user and a personal-only goal. Persist the stable goal UUID, owner ID and immutable payload before sending. The separate dormant SavingGoalCreateIntentJournal now implements local staging (not network delivery); plan-edit intents have their own journal.
2. SavingGoalCreateOnlyRequest validates canonical title (1-120 characters), category, custom category length, positive exact amounts, currency minor-unit precision, date chronology, approved saving rhythm and preferred day. It encodes ONLY existing goal insert fields: id, title, category, custom_category, target_amount, currency_code, start_date, target_date, rhythm, preferred_saving_day, planned_contribution_override.
3. user_id, plan_revision, created_at and updated_at are NOT client-supplied. Database must derive user_id from auth.uid() with RLS and initialize server-owned revision 0. The request holds expected owner locally for independent verification, not JSON authority.
4. After separately approved backend migration and signed old-client compatibility rollout, use INSERT-only with original UUID, NEVER goal UPSERT. A duplicate UUID cannot be assumed to represent a matching goal.
5. On success, ambiguous timeout or duplicate-key response, first recheck Auth user, then fetch a FRESH RLS-filtered server goal SELECT by UUID and authenticated owner. Recheck Auth after response. Never validate cached local data as cloud evidence. A transport error is not a nil row.
6. Decode SavingGoalAuthoritativeCloudRow including owner, goal UUID, plan_revision and all original canonical plan fields. SavingGoalCreateReadbackVerifier.verify requires identical owner/goal, revision zero, exact Decimal amount and currency, title/category/custom field, start/end instants, rhythm, preferred day and future contribution. PostgreSQL UTC Z, +00:00 and fractional-second timestamps can compare as instants.
7. Only this full match proves the first create currently equals the remote row. Missing, invisible, modified or remotely-revised rows fail closed. No fresh UUID, no overwrite and no saved toast merely because INSERT was attempted.

## Recovery matrix

| Server observation | Result | Next action |
| --- | --- | --- |
| Exact matching row with plan_revision=0 and correct owner | Verified initial goal | Complete local reconciliation only after user-approved rollout |
| Nil row after authenticated successful SELECT | Missing or invisible | Keep pending create, investigate; no blind second insert |
| Network failure or changed Auth identity | Unknown outcome | Keep original UUID, reauthenticate and fetch again |
| Duplicate UUID / HTTP 409 | Unknown outcome | Read and compare the canonical server row |
| Different owner or goal UUID | Possible cross-account/corrupt response | Reject, never send another owner's request |
| Remote revision >0 | Goal modified after initial creation | Fetch latest state, show conflict choices |
| Any metadata/currency/amount/date difference | Payload mismatch | Do not UPSERT; user decides how to reconcile |

## Migration and safety gates

- Live Supabase does not yet contain plan_revision. Decoder is not compatible until staged backend #81 is approved and deployed behind a signed upgrade/compatibility plan. This branch does NOT call the new reader or WRITE the database.
- Current production saving_goals.upsert(onConflict: id) is unchanged. Backend #81 would revoke direct UPDATE and therefore break old client sync. Do not enable either half independently.
- Itemized budget, focus and lifecycle are local-only: this contract does not provide full Manage Plan V2 restore or atomic budget-item updates.
- This code does not modify historical saving events, XP, badges, transfers, bank balances or Money Out. Initial-create pending JOURNAL is now implemented but unwired. Authenticated network orchestration, SwiftData reconciliation/cleanup, UI handling, true concurrent sessions, signed A/B backend tests and iOS simulator QA are NOT implemented.
- Actual local SQL/postgres validation of the separately drafted CAS proposal is tracked in PR #81.

## QA while Mac runner is paused

The Linux-only Swift compiler harness scripts/test_issue80_create_only_readback.py exercises the actual source DTO and readback parser with synthetic data. Cases include allowlisted JSON keys, exact Decimal minor-to-major units, nullable keys, wrong owner, wrong goal, remote revision advance, missing row, altered plan fields and timestamp formats. This is NOT a full iOS build or a production authenticated query.

No merge or deployment may be inferred from passing these checks.


## Dormant pending-create state machine

The local queue is SEPARATE from the versioned plan-edit journal. Each owner has one atomic JSON file under Application Support / PipoPendingGoalCreates. iOS writes use complete file protection unless open; the Linux test uses temporary files. This is a local delivery journal, not authenticated server proof or cryptographic account isolation.

- staged: preserve original UUID, canonical goal fields and exact minor-unit amount. Timeout/409/relaunch is NOT permission to regenerate UUID, call a different owner, or overwrite an existing goal.
- verified: an authenticated, owner-filtered current remote row matched goal UUID, owner, ALL original fields and revision 0. Even this does not prove that local SwiftData reconciliation completed. No automatic finish method exists.
- conflicted: server-owned goal differs or revision has advanced. Store observed revision; discard only after explicit user confirmation and future UX review.
- missing/foreign/malformed: nil row and identity changes do not advance state. Invalid JSON, duplicate IDs, changed owner, or inconsistent currency amounts fail the entire owner file closed, never silently reset it.

The journal is not wired to app lifecycle, Supabase, UI buttons or background retry; it cannot mutate SwiftData, historical transactions, XP, badges or Money Out. A future network wrapper MUST check signed Auth before AND after an actual RLS SELECT; passing a UUID into this data object is not proof of authorization.

The Ubuntu Swift harness tests atomic persistence, relaunch, duplicate/reused UUID, A/B account isolation, verified create, explicit conflict, unauthorized readback and malformed files. Native Xcode/device/locked-screen and production Auth E2E remain DEFERRED.

Release hold: verified entries deliberately remain until a separate audited SwiftData/local reconciliation and cleanup gate exists. Never clear them based merely on HTTP 200 or readback without local recovery.

## Staging-flagged authenticated API adapter and local-only reconciliation (new)

The current iOS application still has **NO build flag** called PIPO_ISSUE80_STAGING. The adapter methods below are wrapped in compile-time conditional code and therefore **do not exist in regular production binaries**:

- SupabaseService.issue80StageOnlySubmitInitialGoal: verify the locally current authenticated owner, atomically mark the matching pending create as attempted BEFORE any INSERT, recheck account, submit a single INSERT-only payload using the shared Supabase client (JWT + existing RLS), and always follow with owner-scoped SELECT readback even when the network reports a failed/ambiguous insert.
- SupabaseService.issue80StageOnlyRecoverInitialGoal: verify the same authenticated owner and existing pending intent, SELECT the canonical goal by both id and user_id (limit 2), recheck account after awaits, and pass only that result to the journal's strict readback validator. It **never sends another INSERT**; a timeout, missing row, 409, ownership error or malformed server response cannot be treated as a completed create.
- The scoped PostgREST query includes the proposed plan_revision column. It is not available in live Supabase yet, so these methods **must not be compiled/activated** until the reviewed #81 cutover and signed-app compatibility gates have passed.
- No service-role key is used. Auth credentials are provided by the existing Supabase SDK; the server's RLS performs actual authorization. The local currentUser UUID checks are additional account-switch guards, not an alternative to server JWT validation.
- The adapter is designed against the installed Supabase Swift API; full Xcode compilation is **still deferred**. Ubuntu compiles the Foundation-only models and exercises the journal; it statically audits the staging switch and INSERT/SELECT shape, but it does NOT compile the Supabase SDK behind that inactive flag.

The create journal now has four states: staged (never attempted), attempted (INSERT may have committed; read back before another network request), verified (exact current revision-zero server row), conflicted (known owned row differs). The attempted state is persisted first. An ambiguous timeout always leaves the original UUID. A second attempt to mark it for INSERT is rejected by the journal.

**Pure local reconciliation:** SavingGoalCreateLocalReconciler.assess uses a verified create intent and a caller-provided local snapshot. Cross-account data throws, while mismatched local goal metadata or unresolved edits return local conflict. Unsent saving events and local-only budget items remain explicitly pending. Even an exact match with no unsettled events yields only "eligible for explicit reconciliation", never an automatic SwiftData mutation, XP award, deletion of the journal, or cloud-save status.

### Remaining safety gates

1. Independent security review of #81's definer RPC, #29 append-only ledger, and the old installed client UPsert compatibility problem.
2. Actual authenticated A/B staging POST and RLS SELECT tests, simultaneous-device races, missing session after account switch, and backend version validation.
3. A reviewed and crash-safe **local SwiftData commit + journal cleanup protocol**, including event/XP/budget preservation across relaunch and retry. This is intentionally not implemented.
4. The final UI/offline status flow, native Swift compiler against the installed Supabase SDK, iOS simulator + locked-file test, and owner approval. Mac runner stays deferred.

**No production data was written during this preparation.**


## Staging-only SwiftData Reconciliation Commit & Cleanup V1

After authenticated remote INSERT/SELECT confirms the original create at server revision zero, the goal must ALREADY exist in persistent SwiftData. Reconciliation intentionally does NOT insert, update, delete or save a SwiftData goal, contribution, budget item, badge, or XP.

New dormant components:

- SavingGoalCreateSwiftDataCommit.finalizeAfterFreshCloudReadback, in Pipo/Models/PersonalGoal.swift under the undefined PIPO_ISSUE80_STAGING compile flag, first requires a fresh owner-authenticated server readback. Then it opens a separate new ModelContext(modelContainer) and checks the goal that was already persisted.
- Rejects missing/duplicate local goal UUID, incorrect owner, group goal, invalid monetary precision, changed goal fields/lifecycle, nonzero progress and any attached saving transaction (including another owner's malformed event).
- Reconstructs the canonical request from the locally persisted PersonalGoal. Unsent saving events, SubItem budget rows, and unresolved local edits prevent completion. No hidden overwrite, XP award or history mutation.
- SavingGoalCreateIntentJournal.markLocalCommitVerified only changes a verified entry to a durable terminal reconciled receipt via atomic file write. pending(for:) hides reconciled receipts while all(for:) retains them. Repeating the same UUID after relaunch never stages another INSERT.
- A crash before the atomic receipt transition leaves verified, safe to retry; a crash after leaves reconciled. Repeating the exact confirmed transition is idempotent. Account changes, missing proof or unsynced events must fail closed.

This is deliberately a narrow first-goal NO-WRITE local reconciliation, not general cross-device download/merge, old-app migration or plan-edit CAS. Keeping the terminal receipt prevents duplicate creation but currently counts toward a bounded 100-entry per-owner history. Retention/pruning and deletion cleanup require a separate security review before broad rollout.

The staging SwiftData adapter itself has NOT been compiled with Xcode, because Mac runner use is deferred. Linux compiles/runs the actual Foundation-only contract/journal and statically checks that native staging code does not save/insert/delete models. Real iOS SwiftData, file protection, signed A/B Supabase staging and old-client compatibility remain release gates.

Production: the PIPO_ISSUE80_STAGING flag remains unset; no live app call sites, no database migration, no merge, no enabled Save or Money Out.
