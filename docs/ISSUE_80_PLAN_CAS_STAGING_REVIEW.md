# Issue #80 — Server-owned plan revision and CAS (review-only)

Status: 22 Nov 2026. STAGING DESIGN ONLY. No live SQL, paid branch, iOS changes, simulator, Mac runner, or merge.
Issue: https://github.com/muhammadihsan-byte/pipo-gamification/issues/80

## Existing system and blockers

- Baseline main SHA: 5995e89796345a4ca8740c7e75b71d7349b1c8dc.
- Pipo/Core/Network/SupabaseService.swift currently does saving_goals UPSERT on conflict id. That call can overwrite stale goal metadata and is INCOMPATIBLE with revoking UPDATE. Do not ship this SQL before a compatible client rollout.
- Supabase saving_goals has owner-scoped RLS and immutable currency but no revision column. Historical saving_transactions still allows authenticated owner UPDATE/DELETE on live Supabase. The #29 review-only append-only ACL must be staged FIRST.
- Existing remote goal payload does not include budget breakdown, goal focus/lifecycle, or past rhythm history. This proposal cannot claim full Manage Plan V2 cross-device restoration.

## Proposed staged changes

1. After #29 staging ACL, create a server-owned nonnegative bigint plan_revision, default 0, with BEFORE INSERT trigger forcing 0 even if the client submits 999. Existing rows start at 0.
2. Add private.pipo_plan_revision_receipts, keyed by (owner_id,request_id), with RLS enabled and no client grants. Persist expected revision, canonical JSON request, accepted revision and original response in the same transaction as goal edit.
3. Add public.pipo_apply_plan_revision_v1 as an authenticated-only SECURITY DEFINER RPC with empty search_path, explicit auth.uid() owner checks, and SELECT FOR UPDATE goal lock. Only target amount, target date, rhythm, preferred saving day and future contribution override can change; currency, owner, historical savings and XP never change.
4. Compare expected revision atomically. Exactly one concurrent edit from the same version can commit; losing requests get conflict with current revision and no mutation.
5. An exact retry of the same request UUID, goal, expected revision and canonical payload returns the original receipt, even if newer revisions exist. Reusing UUID with different content raises SQLSTATE 23505. Timestamp equality in request receipts uses epoch seconds, independent of client/PostgreSQL display time zone.
6. At the SAME staged cutover, remove ordinary authenticated UPDATE on saving_goals and the old UPDATE policy. Otherwise a modified client could bypass CAS. Old goal-first UPSERT will fail; this is an intentional hold gate, not a production-ready rollout.
7. Maintain the immutable goal currency trigger and account-owned read/insert. Do not change the Auth-admin deletion cascades.
8. CRITICAL #42 compatibility discovered by disposable PostgreSQL QA: the preexisting contribution INSERT trigger uses a SECURITY INVOKER SELECT FOR UPDATE goal lock; revoking goal UPDATE breaks saving inserts. The proposed stage cutover therefore replaces the existing guard with a tightly restricted SECURITY DEFINER trigger, explicitly checks the authenticated contribution owner, preserves the original immutable-event comparison, and takes the same owner-goal row lock used by CAS and Money Out. This is a HIGH-RISK privileged-function review point: independently verify trigger execution, privileges, RLS, deposits under load and account deletion before production. Do not restore direct UPDATE grants to solve it.

## RPC contract

Inputs:
- p_request_id UUID: persist on device before network attempt; never regenerate on retry
- p_goal_id UUID: must belong to the authenticated account
- p_expected_revision bigint: nonnegative known server revision
- p_target_amount exact PostgreSQL numeric (not authoritative Double)
- p_target_date timestamptz
- p_rhythm daily / weekly / biWeekly / monthly / flexible
- p_preferred_saving_day nullable smallint
- p_planned_contribution_override nullable exact numeric

Applied response: status=applied, request_id, goal_id, currency_code, accepted_revision, target_amount, target_date, rhythm, preferred_saving_day, planned_contribution_override.

Stale response: status=conflict, goal_id, current_revision. No ledger or goal write occurred. Client must refetch the owned goal, show before/after differences, and let user explicitly reapply, edit or discard. New edit uses a NEW UUID and the latest revision. Do not silently overwrite.

Errors: 42501 for missing/foreign goal; 22023 for missing, impossible, excessive-precision or bad-rhythm request; 23505 when same UUID is reused for another request. Authentication/session change must fail closed. A replayed success receipt might no longer describe the latest state, so client must refetch the current goal before marking current local status.

## Non-negotiable rollout gates

- Initial goal create uses INSERT-only with stable UUID. It needs a server receipt/read-after-write path for ambiguous success. Existing UPSERT must be retired before this migration.
- Implement exact-decimal networking and response decoding, account-scoped durable pending requests, and explicit conflict/recovery UX. Offline pending cannot be labelled cloud saved.
- Budget breakdown currently exists only locally. Plan target may not be enabled for full V2 editing until a versioned remote budget-item model and all-or-nothing commit are designed; otherwise breakdown and target may diverge.
- Do not add metadata update bypasses, money-out writes, FX conversion, XP rewards or history mutation.
- Signed old iOS app compatibility requires a reviewed phase-out/bridge plan; an uncoordinated privilege revocation would break existing cloud syncing.
- #29 append-only journal, #16 corrections, #42 Money Out ledger, and #28 billing entitlements remain separate release gates.

## Test matrix — not executed on a real staging database

Files:
- supabase/proposals/issue_80_plan_revision_cas_REVIEW_ONLY.sql
- supabase/local_qa/test_issue80_plan_revision_STAGING_ONLY.sql
- scripts/test_issue80_plan_cas_proposal.py

A disposable local/staging Supabase with real Auth support is required. The SQL fixture is transactional BEGIN/ROLLBACK and explicitly requires an external staging-only custom GUC. Never run synthetic Auth inserts on the connected production project.

1. Run staged #29 ACL, then #80 cutover. Preflight must stop on unexpected RLS, schema or trigger drift.
2. Auth A creates IDR goal while spoofing plan_revision=999; the server stores 0.
3. A submits revision 0 valid plan; returns applied revision 1. Exact UUID replay returns same original revision 1, with no duplicate receipt or mutation. Another UUID expecting revision 0 returns conflict. Reused UUID with changed payload fails.
4. A fractional IDR plan is rejected. A direct SQL UPDATE to owned saving_goals is denied. Historical savings/XP and currency remain untouched.
5. Auth B cannot SELECT/UPDATE A goal or invoke RPC on it. A different account may reuse the UUID without cross-account data exposure.
6. Auth-admin account deletion must cascade to goals, journal and private receipts; no orphaned financial planning records.
7. TRUE CONCURRENCY: use TWO committed sessions signed in as A. Both read revision N, then simultaneously submit distinct UUIDs at N. Exactly one should apply at N+1 and one should conflict. The single-session rollback fixture cannot prove this.
8. Test ambiguous network success, identical retry, later successful edit then first-ID replay, offline/relaunch account A-B switch, missing revision, old client rejection, direct PostgREST bypass, and invalid currency precision.
9. Verify staging advisors, grants, account isolation, backup/rollback and independent SECURITY DEFINER review before any production authorization.

The earlier quoted Supabase staging branch had a nonzero hourly fee; DO NOT create paid staging without explicit approval. No macOS/iOS CI is needed for this design-only branch.

## Known exclusions and approval

This is a proposed contract, not a verified migration or finished implementation. It does not provide real server tests, signed A/B session evidence, dual-device conflict recovery, budget synchronization, automatic restoration or live saving reconciliation.

Hold all merges, live migrations, release, Money Out enablement, and Manage Plan Save until the user approves the reviewed implementation and staging gates.
