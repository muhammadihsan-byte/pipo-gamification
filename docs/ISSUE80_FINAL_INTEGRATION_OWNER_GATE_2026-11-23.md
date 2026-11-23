# Pipo — Integrated CAS, Account Isolation, Offline Recovery & Global QA

**Date:** 2026-11-23. **Status:** integrated source-only candidate, draft PR #92; no migration or StoreKit enablement. Owner's final approval applies to source merge only; production SQL and enabling app features remain separate decisions.

## Branch and dependency map

- `main` baseline: Pipo live legacy `saving_goals` with owner RLS, no `plan_revision`; live current-client path uses `saving_goals.upsert(onConflict:"id")`.
- Integrated review branch (PR #92) is based on PR #85 head `dd2f343`: incorporates PR #84, #83, which consolidated PR #79, #81 and #82. This is **not evidence those component PRs were merged**. Do not merge the originals independently as a workaround.
- CAS and Budget V2 proposals remain `REVIEW_ONLY.sql` and the client code dormant behind undefined `PIPO_ISSUE80_STAGING` / `PIPO_ISSUE80_BRIDGE` flags.
- Pay Schema/Apple verifier drafts #90/#91 are **not included** in this integration and remain unmerged; no Apple Developer account is required for this safety/UX QA.

## Changes in this final integration candidate

1. **App Group widget privacy:** On sign-out, always remove the physical snapshot, even if a previous legacy session forgot its active account key. Refuse ownerless private titles, XP, progress, schedules, recording counts and cadence. Owner B cannot display or write owner A's snapshot.
2. **Transient financial UI isolation:** On account switch clear pending record amount, invalid/validation text and focus, stale alert, saving sheet, submitted state and milestone/reward display. The saved SwiftData ledger/XP remain untouched.
3. **Regression gate:** `scripts/test_issue80_final_account_safety.py` compiles the actual production `WidgetSharedData.swift` using `swiftc` on Linux, checks owner A/B, ownerless payloads, legacy account marker and physical removal. Additional source gates ensure account checks, explicitly dormant CAS/bridge and no enabled Money Out/Save.
4. **CI optimization:** Default PR Fast Checks run Foundation-only Swift/SQL contract tests on Ubuntu; disposable postgres:17 and local GoTrue signed A/B budget/CAS regression are scoped to relevant paths. Native iOS validation remains conditional on a deliberate non-draft QA transition and uses one existing macOS run; no repeated unconditional macOS push builds.
5. **Global Experience/Accessibility:** Focused native test route includes existing 320pt/Dynamic Type/VoiceOver *tree* and USD goal/currency/Manage Plan simulator XCTest with MP4. No new unapproved design variants.

## Intended acceptance matrix

| Gate | Proof required | Cannot infer |
|---|---|---|
| Swift Foundation local account scope | owner A/B widget data, stale key, physical logout purge, ownerless rejection, pending UI clear | Native widget process/physical iPhone |
| CAS and offline journals | compile actual Swift contracts on Linux, pending/retry, crash relaunch, UUID invariants, mismatched receipt rejection | Production client wired to CAS |
| PostgreSQL revision and budget | two genuinely independent DB sessions; A wins, B stale; original receipt retry; atomic budget; no XP rewrite; Auth erase | Apple or live Supabase migration |
| Real signed local Auth/PostgREST A/B | signed JWTs, owner/cross-owner RLS, direct UPDATE denial after disposable CAS cutover | Installed old binary compatibility |
| Native iOS/SwiftData & UX | Xcode build+unit tests, 320pt Dynamic Type, VoiceOver tree, USD goal; Manage Plan disabled Save; widget/account tests; MP4 | VoiceOver physical-device audit, App Store signing |
| Source review and merge | exact-head CI green, PR diff reviewed, final user approval | Production SQL, Apple checkout or entitlement release |

## Key remaining product/security decisions (hold for deployment)

- Old installed binaries still UPSERT. The review-only #81 migration revokes direct UPDATE, so applying it now would break those clients. A signed release bridge, installed-client adoption threshold, forced upgrade/rollback plan and controlled rollout decision must precede migration. A new bridge flag protects only a new app build; it does not repair old binaries.
- Full plan Save cannot be activated until a production-approved server CAS+Budget V2 schema exists, budget import is expressly user-reviewed, conflict UX is designed/approved, local SwiftData applies verified remote snapshots, and signed two-device offline/reinstall QA passes.
- Apple Developer is **not needed** for simulator builds with `CODE_SIGNING_ALLOWED=NO`, but App Store/TestFlight signing requires it.
- Real device VoiceOver, privacy erasure of every offline journal for a deleted account, account switch while syncing, delayed network acknowledgements, cross-device Restore and legacy ownership reclaim are independent release gates.
- The integrated visual PR #79 must retain owner design approval. Source-level green checks do not approve its appearance by themselves.

## Approval checklist

- [ ] Exact final head: PR Fast Checks success (full Swift contract suite).
- [ ] Exact final head: disposable PostgreSQL and signed local Auth A/B both success.
- [ ] Exact final head: controlled iOS build/Unit XCTest and focused simulator a11y/global QA pass; screenshot/MP4 inspected.
- [ ] Source and review-only SQL differences reconciled against staged old-client contract.
- [ ] Owner explicitly grants **one final merge approval** for PR #92, with clear exclusions for release/production migration. Neither PR #90/#91 nor any live SQL becomes approved implicitly.

**No real financial movement:** Pipo records self-reported savings only.
