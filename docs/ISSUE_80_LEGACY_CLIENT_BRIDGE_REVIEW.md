# Pipo #80 — Legacy-schema bridge candidate and signed rollout gate

**Status:** Isolated **draft/review-only** client implementation, not a signed binary, App Store submission, backend migration or production Save enablement. Branch: `feat/issue80-signed-legacy-client-bridge-review`, stacked above PR #84 and #83.

## Supported deployment stage

This bridge is intended for the **existing schema BEFORE #81/CAS migration**, while signed legacy clients still use `saving_goals.upsert(onConflict: "id")`. The current production goal schema has owner-only RLS but no `plan_revision`.

It is compiled only when `PIPO_ISSUE80_BRIDGE` is explicitly defined for an approved signed app build. This repository does **not** define that flag in Release or Debug. When it is absent, existing `syncPersonalSavings` behavior is unchanged. The bridge cannot be marketed as enabled/shipped merely because its source has been merged.

## Candidate bridge behavior under explicit flag

1. Build and validate a frozen, exact-minor-unit, owner-scoped set of goal create requests **before network awaits**. Transactions remain independently immutable ID-based appends.
2. For each personal goal, fetch a **fresh, authenticated, owner-filtered** legacy `saving_goals` snapshot (no `plan_revision` field) and check Auth user both before and after every awaited request.
3. If a goal exists, require exact match for UUID, owner, title, category, target, immutable currency, dates, rhythm and contribution preference. Never use `UPDATE` or `UPSERT` to silently reconcile a mismatch.
4. If missing, first persist a complete create request under `Application Support/PipoLegacyGoalBridge/<owner>.json` with atomic protected file writes; permanently retain the goal UUID and payload. Only **one** `INSERT` is attempted automatically. Success, HTTP 409, timeout or cancellation is **not** proof of cloud backup.
5. A new owner-filtered SELECT must verify the exact original goal before marking the journal `verified` or sending transactions for that goal. A timeout with no visible row stays `attempted`; no second INSERT or regenerated UUID occurs. Recovery UI/resubmit policy still needs final product review.
6. If authenticated account changes, owner/goal data differs, data is corrupt or readback is missing, fail closed. The existing UI can display the cloud backup warning; local goal and saving transaction state are untouched.

## Non-goals and mandatory caveats

- This is **not CAS** and cannot prevent older installed clients from overwriting goal fields during the legacy transition. It simply removes the proposed new client's direct UPDATE/UPSERT behavior. Server revision and idempotency receipt do not exist yet.
- Existing old-client versions still UPSERT. They will fail after the future secure UPDATE revocation; **a signed upgrade window and adoption threshold policy are still required**, with installed-version telemetry and upgrade messaging.
- The bridge knows nothing about server Budget CAS V2 rows; itemized budgets remain local until explicit import/review UI, versioned RPC adapter and native SwiftData reconciliation are approved.
- Pending creates intentionally remain at `attempted` after ambiguous failure, even if the row was not inserted. This favors avoiding duplicate writes over liveness. A reviewed user-driven retry/discard recovery screen is needed before release.
- Journals retain verified receipts (100-entry fail-closed cap), with no compaction/account-deletion cleanup implemented yet. No XP, achievement, badge, balance or transaction is directly changed by this bridge.
- Correct cross-device application behavior after CAS cutover requires **another CAS-aware client version** (or a deliberately controlled mandatory update). This old-schema bridge must not be represented as a full solution to cross-version synchronization.

## QA and release gates

- `scripts/test_issue80_legacy_bridge.py` compiles production Foundation Swift contract/journal logic and runs exact owner, schema-without-revision, mismatch, UUID replay, protected persistence, crash and corrupted-file tests. It does not use real Auth or run app lifecycle.
- Native Xcode compile of `PIPO_ISSUE80_BRIDGE`, signed disposable Auth A/B integration, and edge cases for disconnect/resume, multi-goal partial success and account deletion **must pass** before a signed bridge build is distributed.
- Stage on disposable/authenticated backend before signing. A published signed release additionally needs entitlement/certificates, TestFlight distribution and explicit product-owner authorization.
- Server migration order remains #42 contribution guard, #29 immutable ledger ACL, #81 revision CAS, and then Budget V2, after a compatibility adoption decision. No live SQL or DB grant change is authorized here.
- PR #83/#84 and this bridge remain draft/unmerged until owner approval; merging code is a separate event from deploying an approved signed bridge.

**Do not merge, enable Save or deploy production SQL from green Linux/static QA alone.**

## CI evidence checkpoint

The PR fast and disposable Auth A/B workflows run when the draft is temporarily compared with `main` for integrated evaluation. It will then return to its stacked base (#84); those Linux results are source-head evidence, not a proof that dependent drafts were merged. The one-time macOS native check is separately label-triggered and uses only a temporary Debug flag.
