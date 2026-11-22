# Issue #80 — Offline plan-intent journal and legacy goal-sync cutover

STATUS (22 Nov 2026): DESIGN + DORMANT CODE ONLY. No iOS UI action, SQL deployment, Mac runner, paid staging, merge or TestFlight.

Refs: issue #80; backend proposal draft PR #81; dormant client draft PR #82; immutable journal #29.

## Why this is needed

The currently deployed app uses direct saving_goals UPSERT on UUID. It may overwrite a newer plan from another device; a timeout leaves the client unsure whether its write was accepted. PR #81's compare-and-swap (CAS) SQL would revoke direct goal UPDATE and make existing versions' UPSERT fail, even during normal goal-first saving sync. This must be solved BEFORE a backend cutover, not after. Itemized budget, pause/archive and focus are not in current cloud goal schema.

## Durable account-specific state machine

| State | Meaning | Required next step | Forbidden |
| --- | --- | --- | --- |
| staged | Stable UUID, owner, goal, revision and exact requested fields written atomically before any eventual RPC | After approved rollout, retry EXACT same request; keep pending across relaunch/offline | No "saved" toast, no UUID regeneration or XP award |
| acknowledged | Server applied receipt strictly verified; no current readback yet | Fetch latest RLS-owned current goal, compare all fields and revision | Do not use an old replay receipt as proof current goal matches |
| conflicted | Server returned stale revision | Preserve local draft, show before/after and require explicit reapply/edit/discard | No silent overwrite/rebase/automatic discard |
| corrupted/invalid | Owner, UUID, duplicate goal, fields, state or JSON cannot be verified | Fail closed, keep file and expose diagnosis under future approved UI | Never treat corrupted file as empty queue or leak into another owner |

Implemented in Pipo/Core/Network/SupabaseService.swift without calling Supabase:
- PendingSavingPlanCASIntent stores amount and optional future contribution in exact integer minor units, owner UUID, goal UUID, stable request UUID, expected revision, original currency, target date, saving rhythm, created timestamp, state and response revision.
- SavingPlanCASIntentJournal stores one JSON file per owner inside Application Support/PipoPendingPlanCAS. Atomic writes with iOS file protection; separate from Money Out journal. The local Linux harness writes to disposable temporary files.
- On read, the entire file is validated for account owner, unique request UUID and goal, current state invariants, exact currency precision, positive amounts and date canonicalization. Invalid content fails closed.
- Stage is idempotent for exact original request; same UUID with a different payload is denied, and a second unresolved plan edit for one goal is denied. Queue has a strict size cap.
- Response transition requires the existing verified CAS receipt. Conflict stays pending until explicit user decision. Applied stays acknowledged until a CURRENT owner-validated goal snapshot matches original amount, revision, currency, target date and future rhythm.
- No automatic background sending, SwiftData edits, restoration after uninstall or privileged account action is implemented. Live goal sync remains unchanged.

Security limitations: file protection and owner-specific filenames mitigate accidental mixups but are not cryptographic session isolation. The caller must verify active authenticated owner at time of send/response. On final user account deletion, a reviewed cleanup or quarantine policy for the account's local files is required. Do not put request data into analytics/crash logs.

## Four-phase old-client migration contract

**Phase 0 — preserve existing production behavior (now).**
Keep current goal UPSERT untouched; do not enable CAS Save or Money Out. Build and test standalone DTO and local journal only. Existing local SwiftData records, transaction UUID, XP and achievements remain unchanged.

**Phase 1 — create-only goal and verified restore.**
Design an INSERT-only new-goal path using stable UUID. A timeout must cause owner-scoped canonical readback; no blind UPSERT or "already saved" guess. For pre-existing goals, fetch exact owned remote UUID and revision; if remote metadata differs from device, do NOT overwrite. Represent missing/foreign/corrupt states explicitly. Keep historical savings separate and append-only.

**Phase 2 — true versioned edit and conflict UX.**
In a disposable local/staging Supabase with signed Auth A/B, stage immutable ledger #29 then CAS #81. Test two committed simultaneous plan updates from the SAME revision: one wins, one conflicts. Build user-driven reapply/edit/discard with a new UUID only after latest revision is fetched. Save full budget items atomically with target (currently not in cloud); otherwise full Manage Plan V2 final Save remains blocked. No currency conversion or retroactive XP edits.

**Phase 3 — coordinated signed-app API cutover.**
Inventory installed old versions and test compatibility. Existing goal-first UPSERT needs direct UPDATE privilege but server CAS requires revocation to stop bypass. Define a server version gate, supported-upgrade policy, possible old-app read-only/local-only fallback, backup and rollback before revoking. Avoid claiming zero-downtime compatibility without proof. Never leave direct client goal UPDATE open as a permanent CAS bypass. Obtain user approval before staging/prod SQL.

**Phase 4 — deferred native integration QA.**
When Mac runner use is reapproved, test iOS 17, real device file protection, offline/relaunch/lock, account A-B switch, signed old-client upgrades, budget consistency, conflicting devices, UUID replay, and actual server readback. Local Linux Swift contract tests do NOT replace this gate.

## Readiness and next action

Ubuntu/Swift harness can validate local atomic state transitions without Mac runner. No production RPC has been called, no database schema has changed, and no pending plan is synchronized to cloud by this code.

Next backend-safe task: design a separate, still dormant INSERT-only first-goal request plus authoritative readback and versioned goal snapshot decoder, then test with disposable local PostgreSQL/Auth; do not merge or enable Save until an approved rollout exists.
