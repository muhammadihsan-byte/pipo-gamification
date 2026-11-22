# Pipo #80 — Dormant client CAS contract and rollout compatibility

**Status: contract preparation only · November 22, 2026.** The code in this branch is not wired to any button, normal savings sync, or production RPC. No Money Out confirmation, Plan V2 final Save, server migration, Mac runner or TestFlight is enabled.

References: [Issue #80](https://github.com/muhammadihsan-byte/pipo-gamification/issues/80), [review-only backend draft PR #81](https://github.com/muhammadihsan-byte/pipo-gamification/pull/81), [#29 immutable ledger](https://github.com/muhammadihsan-byte/pipo-gamification/issues/29).

## Preparation delivered

- \`SavingPlanCASRequest\` encodes **only** the eight \`p_*\` RPC parameters matching #81: stable UUID, goal UUID, expected server revision, exact Decimal target major-units, ISO date, rhythm, optional future day, optional exact Decimal contribution.
- \`user_id\` and mutable \`currency_code\` are **not** RPC inputs. The original per-goal currency is kept locally only to validate precision and verify the server response. No FX conversion is performed.
- Validates revision 0...Int64.max-1, positive currency-valid amounts within server limits, approved cadence values, no flexible commitment/day, weekly day <=7, and exact 0-/2-minor-unit amounts.
- Explicitly encodes \`null\` for optional arguments: the Postgres RPC declares positional parameters without defaults and requires every named key, even when null.
- \`SavingPlanCASWireResponse\` decodes \`applied\` and \`conflict\`; \`SavingPlanCASReceiptValidator\` rejects wrong UUID/goal/currency/revision/amount/period/date, treats conflict as **not saved**, and never edits SwiftData. For an exact replay, a verified older applied receipt may not be the current goal state.
- Pure focused XCTest cases have been authored but **NOT run** without macOS. Linux PR Fast Checks extract the production contract into an isolated Swift Foundation build, substitute a minimal currency shim only for its existing app dependency, then test encoding, response, spoof rejection and local journal state transitions without Xcode or network.

## Existing code intentionally unchanged

\`SupabaseService.syncPersonalSavings\` still uses:
\`\`\`swift
.from("saving_goals").upsert(payloads, onConflict: "id")
\`\`\`
This is **not version-aware** and is INCOMPATIBLE with the #81 proposal's staged removal of authenticated goal UPDATE. Keeping it unchanged avoids breaking the currently deployed schema, but does not solve cross-device last-write-wins. The new DTO is not called by \`SupabaseService\` and no plan draft is persisted.

The review-only Money Out adapter is also untouched. No historical saving, XP, badges, achievements, bank transfers or paid-slot code changes.

## Required cutover design: no unsafe dual-write period

1. Introduce a version-aware, insert-only goal-creation path with stable client-generated goal UUID. An ambiguous-success retry must **read back and compare** all canonical fields from the authenticated account; do not blindly overwrite or treat a conflicting UUID as success.
2. Obtain \`plan_revision\` and the owned goal's current currency from the server before editing; bind the local editor to that immutable initial snapshot. The selected goal remains account-scoped and must not be a shared/group goal.
3. The dormant per-account, device-protected atomic plan intent journal is now implemented but UNWIRED. Once rollout is approved, stage BEFORE any RPC, reuse the same UUID on timeout, and never send A's request as B.
4. Send \`SavingPlanCASRequest\` only after the #81 RPC has been approved, deployed, verified with signed A/B credentials and compatible client release policy. After auth call, verify current authenticated account again, then validate receipt and refetch the current revision. Never mark a stale old receipt as the current remote plan.
5. On \`conflict\`, fetch the latest owned goal and canonical saving snapshot; show before/after/affected budget and rhythm, and require user-controlled reapply/edit/discard with new request UUID. Do not silently merge. Offline drafts remain pending.
6. **Budget breakdown is NOT in current remote schema.** To enable the full V2 Save, add server-versioned budget items and an atomic mutation alongside the goal target, so remote target can never diverge from its itemized budget. Preserve saving history, existing XP and achievements.
7. BEFORE server UPDATE grant revocation, deliver a signed app release with an explicit minimum-supported-version gate or compatible server bridge, test existing app installations (including offline/reinstall) and define rollback. Otherwise existing app versions will fail on their normal goal UPSERT; no legitimate release can assume clients auto-update.
8. Cut over to the approved #29 append-only ledger and the #81 server CAS atomically under a separately authorized migration and verified two-session concurrent conflict QA. Do not leave authenticated direct UPDATE available as a bypass.

## Test coverage and outstanding gates

- Linux static and extracted Swift contract tests: automated by \`PR Fast Checks\` on Ubuntu; **not** iOS Xcode compilation and not a live authenticated RPC test.
- iOS-only XCTests: written, deferred until Mac runner is allowed.
- Actual RPC concurrency, old-client cohort testing, first-goal insert receipt path, auth-wired pending delivery, owner switch/reinstall, live Data API RLS, SwiftData conflict UI and versioned budget: **not implemented here**. The dormant local journal itself is implemented.
- The SQL proposal #81 has passed independent disposable PostgreSQL and loopback-only Auth/PostgREST QA on its previous exact commit. It is still unmerged, not deployed and lacks true two-session concurrency proof.

**Do not merge or deploy this preparation branch as proof that server-authoritative Manage Plan is finished.** Independent security review and user final merge approval are required.

## Offline journal and old-client migration addendum

See [ISSUE_80_OFFLINE_PLAN_JOURNAL_AND_SYNC_CUTOVER.md](ISSUE_80_OFFLINE_PLAN_JOURNAL_AND_SYNC_CUTOVER.md) for the dormant state machine, crash recovery, per-account isolation, and the staged migration plan. This does NOT enable production plan saving.
