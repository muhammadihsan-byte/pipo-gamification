# Issue #80 — Create-Only Goal + Verified Cloud Readback (dormant)

STATUS: REVIEW ONLY. No production backend changes, live CREATE/SELECT calls, Mac runner, or merge. Works with draft PR #82. Backend revision and CAS SQL proposal is separately reviewed under draft PR #81.

## First goal creation contract (future, currently UNWIRED)

1. Require current verified Supabase Auth user and a personal-only goal. Persist the stable goal UUID, owner ID and immutable payload before sending; the current dormant plan-edit journal does NOT handle new-goal creation yet.
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
- This code does not modify historical saving events, XP, badges, transfers, bank balances or Money Out. Initial-create pending journal, verified authenticated network orchestration, UI handling, true concurrent sessions, signed A/B backend tests and iOS simulator QA are NOT implemented.
- Actual local SQL/postgres validation of the separately drafted CAS proposal is tracked in PR #81.

## QA while Mac runner is paused

The Linux-only Swift compiler harness scripts/test_issue80_create_only_readback.py exercises the actual source DTO and readback parser with synthetic data. Cases include allowlisted JSON keys, exact Decimal minor-to-major units, nullable keys, wrong owner, wrong goal, remote revision advance, missing row, altered plan fields and timestamp formats. This is NOT a full iOS build or a production authenticated query.

No merge or deployment may be inferred from passing these checks.
