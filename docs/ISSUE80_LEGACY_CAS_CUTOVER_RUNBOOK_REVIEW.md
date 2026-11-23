# Pipo #80 — Legacy Client Compatibility & CAS Cutover Runbook (REVIEW ONLY)

**Prepared:** 2026-11-23. **Execution state:** design + local disposable QA only.
**Production deployment:** NOT AUTHORIZED. **Native flags:** OFF. **Merge:** requires owner final approval.
**Source branch:** `review/issue80-legacy-cutover-readiness-v1`.

## Verified production preflight, read-only

Supabase project `jdboaaiiwkblxvejnhol` (Singapore) was checked via a SELECT-only audit:

| Finding | Actual reading | Release meaning |
|---|---|---|
| `public.saving_goals.plan_revision` | Missing | CAS is not installed |
| `pipo_apply_plan_revision_v1` / `pipo_apply_plan_budget_v2` | Missing | No secure RPC path |
| Authenticated direct goal UPDATE | Granted; owner UPDATE policy present | Installed legacy UPSERT currently works and can overwrite same-account goal |
| Authenticated saving transaction UPDATE | Granted | #29 immutable history cutover not installed |
| Current saving goals / transactions | 0 / 0 at audit | **Not** evidence of zero installed clients or zero pending offline edits |

Production inventory is a point-in-time read, **not** automatic authorization to alter grants. Avoid posting customer IDs, names, app tokens or signed JWTs to issues.

## Compatibility problem

Current normal iOS `SupabaseService.syncPersonalSavings` performs:
`saving_goals.upsert(payloads, onConflict: "id")` and then owner-scoped saving transaction insert-ignore.
The feature-flagged legacy bridge uses frozen INSERT-only goal requests, disk journal and exact authenticated SELECT readback; **it is not active in any normal build**.

The #81 SQL proposal revokes authenticated goal UPDATE **and** drops the owner UPDATE policy in the same transaction. That is necessary for a secure CAS boundary, but existing signed clients that still perform legacy UPSERT will receive an authorization error, **even if no goal plan was intentionally edited**. A mere schema change is not enough to make their backup work.

The #29 ledger ACL can be staged before #81 only after a separately approved signed-client compatibility review; #29 goal UPSERT remains possible while immutable transaction event updates are revoked. Any older client with transaction `merge-duplicates` behavior may also need upgrade, so do not assume #29 is universally backward compatible.

## Verification added in this branch

Local Supabase CLI test `scripts/local_authenticated_issue80_cas_qa.py` uses **real signed Auth A/B users and PostgREST**, with loopback-only API and database safeguards:

1. **Before #29/#81:** Alice's old `POST saving_goals?on_conflict=id` with `resolution=merge-duplicates` creates and **overwrites** her own synthetic goal. Bob cannot overwrite it. This proves the known stale-writer problem.
2. **After #29, before #81:** Alice's legacy goal UPSERT still works. The test verifies that the immutable history ACL does not accidentally revoke goal UPDATE ahead of the migration window.
3. **After #81:** Existing legacy row gets `plan_revision=0`; legacy UPSERT must fail with `42501`, and its amount and revision must remain unchanged. A new owner-authenticated CAS request updates that same historic row to revision 1.
4. Existing signed A/B, stale-edit, replay UUID, foreign-owner rejection, immutable XP and 2-session race tests continue running. Budget V2 signed tests still prove CAS V1 endpoint is revoked and OLD UPSERT is denied.

Both SQL proposals remain under `supabase/proposals/*_REVIEW_ONLY.sql`; NO production migration is generated or applied here.

## Release paths: signed clients exist vs never distributed

**Case A — Any signed legacy binary distributed:** Even ad-hoc/enterprise installations and devices with a local signed old build count. Publish and validate an approved bridge/compatible release **first**; determine active version cohorts without exposing financial data. Do not revoke UPDATE until no legacy/unknown-version active clients remain in the agreed measurement window, the new build's offline recovery and signed A/B tests pass, and owner separately authorizes the production operation.

**Case B — Officially no prior signed distribution:** Obtain independent evidence from the App Store/TestFlight distribution inventory **and** prior ad-hoc/enterprise/developer-device builds. Production DB row count 0, empty GitHub release tags and user recollection alone cannot establish this. The review-only readiness gate accepts this alternate path only with explicitly documented inventory evidence. The user has not configured an Apple Developer account yet, so this evidence currently cannot be verified.

**Case C — Uncertain distribution history or unknown clients:** **NO GO**. Leave UPDATE grant unchanged; keep the preview-only Manage Plan and current cloud backup limitations visible. Never deliberately break old clients just to make the CAS tests green.

## Proposed staged deployment plan (NOT a command to execute)

1. **Freeze/observation:** Resolve any pending sync/backlog, open incidents, old-client cohort measurements, consent/privacy for version-only telemetry, and signed device matrix. Inventory binaries; identify the *minimum* version which uses INSERT-only creation and V2 CAS for edits.
2. **Bridge readiness:** Xcode native compile with `PIPO_ISSUE80_BRIDGE` in a controlled **test configuration only**. Verify account switch, airplane mode, ambiguous timeout, relaunch, per-goal partial success, duplicate UUID, readback mismatch, 100-entry journal cap, account deletion and upgrade from an actually signed old build. Design user-driven recovery and upgrade notice before publishing. Do not enable flag in a general Release by default.
3. **User adoption:** Publish compatible signed client (requires Apple Developer signing setup), instrument privacy-minimal authenticated version/capability cohorts, use at least **14 days** of observation, and require **zero observed legacy/unknown active users** with meaningful active coverage. If coverage is zero, this is not proof of adoption. A 48-hour-old last observation is stale. These windows are conservative proposed gates, not measured Pipo statistics.
4. **Disposable staging dress rehearsal:** Reproduce sanitized schema, signed users, app client versions, offline queues and rollback. Apply #42 contribution guard → #29 immutable ledger → #81 revision CAS → Budget V2 in the reviewed order. Test compatibility both sides, staged backups and **actual restore drill**, no private schema exposure, all RLS grants, and ability to fix forward.
5. **Separate production approval:** Owner reviews populated evidence manifest, signed client inventory, proposed maintenance window, SQL hashes, backup/restore evidence, incident on-call and rollback plan; explicitly authorizes the exact production migration. This is **NOT** implied by source merge.
6. **Controlled cutover:** Set a maintenance/freeze window that prevents clients from writing into the temporary #81 CAS V1-only phase before Budget V2 is applied and postflight verified. The proposals currently have independent `BEGIN/COMMIT` blocks; do not pretend they are one transaction. If a truly atomic combined cutover is required, author and test a **new reviewed combined migration** before execution. Never improvise live SQL to resolve drift.
7. **Rollout/unfreeze:** Verify latest signed client can create, fetch, apply budget CAS with explicit import acknowledgment, confirm remote readback, preserve historical savings/XP and handle conflict without silent merges. Only then consider activating final Save UX with its own design approval. Continue read-only measurements and error monitoring.

## Rollback and outage playbook

- **Do not automatically GRANT UPDATE back** to old client versions: that would reopen the same-account last-write-wins bypass around CAS. Treat it as a fresh security approval decision if unavoidable.
- For failed schema preflight or partial upgrade, **stop and keep UI Save disabled**; use reviewed, tested forward-fix procedure while maintaining owner-scoped readback and local pending journal.
- If a client request times out, its UUID and draft remain pending, never show a synced label from an HTTP success alone; obtain current signed readback and verify revision and every budget row.
- If a user reports old client backup failure, preserve their local data and offer supported-version upgrade/help; do not regenerate UUID, delete saving history or claim recovery succeeded.
- Backups must include Auth/goal ownership and journal considerations; a restore plan must be proven in a disposable environment before a production cutover decision.

## Evidence gate commands (read-only, no external credentials)

```bash
python3 -m unittest -v scripts/test_issue80_cutover_readiness.py
python3 scripts/issue80_cutover_readiness.py --evidence docs/issue80_cutover_evidence_REVIEW_TEMPLATE.json
```

The second command intentionally exits with **code 2 BLOCKED** for today's empty review template. Populate evidence only after independent inspection of signed-build QA, adoption metrics and backup/rollback. `evaluate()` merely checks **presence/format/age**, not cryptographic authenticity; human review is mandatory even if it prints ready.

## Hard release gates currently BLOCKED

- Apple Developer/signing/distribution inventory not available.
- Existing compatible bridge source not signed, enabled, field-tested or distributed.
- No active-client version telemetry or complete old-client inventory.
- Budget import UX, CAS conflict recovery and final Save remain review-only.
- No confirmed backup/restore dress rehearsal or approved real-user incident plan.
- Physical iPhone VoiceOver, signed two-device rollback/reinstall, local journal deletion and offline recovery remain outstanding.
- Live CAS and ACL SQL untouched, production approval **not granted**.

**Deliverable:** a reviewable safe rollout decision, genuine signed local compatibility evidence and hard preflight guard. It is **not** a finished production CAS release.
