# Pipo — Cloud Saving Data Integrity Checkpoint (Issues #29 / #16 / #42)

22 November 2026 · based on iOS `main` `31533a8`.

## Current verified production schema — read-only

Supabase project `jdboaaiiwkblxvejnhol` has `saving_goals`, `saving_transactions` and `user_profiles` with RLS enabled, composite account-owned goal→transaction FK, and an applied per-goal immutable currency migration. At this checkpoint, **zero live goal and transaction records** were reported; there is no authenticated A/B end-to-end acceptance proof.

`saving_goals` still has no server-generated revision/ETag for compare-and-swap. Current iOS goal UPSERT can overwrite a changed remote plan. `saving_transactions` exposes UPDATE/DELETE under pre-existing policies, so a malicious or stale client can mutate history independently of our app. Local SwiftData and cloud reward state are not yet reconciled safely across devices.

## Scope delivered by the first code PR

- Ensure every locally generated authenticated batch has **unique transaction UUIDs**, even across two distinct owned goals. On collision fail the entire batch before calling Supabase.
- For *transaction upload only*, switch `upsert(onConflict: "id")` to `upsert(onConflict: "id", ignoreDuplicates: true)`. Retries that reuse the original UUID now leave the existing remote amount, date, goal, and XP columns unchanged.
- Keep goal-first insertion, account ownership and currency validation, and the existing best-effort offline retry. **No old journal rows or XP are edited.** Existing user goal revisions are still not protected by CAS and must not be called conflict-safe.

## Explicitly **not** solved by this change

1. `ON CONFLICT DO NOTHING` can hide a *mismatched* UUID event; it protects remote history from overwrite but is **not proof the client's row matches the server's**. The release implementation needs an account-scoped read-after-write digest/receipt comparison backed by immutable server-side storage.
2. Introduce server-side append-only rules (revoke client UPDATE/DELETE, audited migration, deletion-cascade review) only with separate owner approval, shadow migration/dry-run and two disposable authenticated accounts.
3. Replace mutable goal metadata UPSERT with server-authoritative per-goal version + CAS rejection/merge UX, including account-switch, offline/reinstall and concurrent iPhone edits. No last-write-wins.
4. Add append-only correction/reversal events to #16 and Money Out under #42; calculate progress from canonical owned ledger, not mutable `currentAmount`. Badge/XP grants require authoritative idempotent event derivation and explicit recovery policy.
5. Test with actual signed iPhone A/B accounts and verify production RLS cannot be bypassed. No simulated CI report proves live backend concurrency correctness.

**No production SQL/migration, paid billing, TestFlight, or App Store release is authorized by this PR.** Leaving the remaining requirements explicit is deliberate; production safety cannot be inferred from an iOS-only green CI.
