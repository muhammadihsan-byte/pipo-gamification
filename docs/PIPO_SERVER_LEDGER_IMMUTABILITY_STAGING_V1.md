# Pipo #29 — Staging-only immutable contribution ACL hardening

Verified read-only on 22 Nov 2026 against connected Supabase project `jdboaaiiwkblxvejnhol`: authenticated currently has UPDATE/DELETE on `saving_transactions` and DELETE on `saving_goals`. The journal FK to goals is ON DELETE CASCADE. These privileges permit an account to erase or mutate its own canonical history by bypassing the iOS client. App-side PR #74 has already made transaction retries ON CONFLICT DO NOTHING but cannot override backend privileges.

## Proposed server patch (NOT applied)

**Review-only SQL:** `supabase/proposals/issue_29_immutable_contribution_acl_REVIEW_ONLY.sql`.

1. Verify known policy names, RLS, FK CASCADE semantics and schema; abort on drift.
2. Revoke UPDATE/DELETE from `authenticated` on transactions; revoke goal DELETE. Remove matching RLS policies. Keep transaction SELECT/INSERT, goal SELECT/INSERT/UPDATE. Existing #74 idempotent retry continues to use INSERT ON CONFLICT DO NOTHING.
3. Add a security-invoker goal identity trigger preventing ID, owner, or created_at mutation while preserving legitimate title/target/rhythm edits.
4. Keep `auth.users ON DELETE CASCADE` and the authenticated Edge Function's privileged admin deletion path. **Do not alter FK constraints or execute delete from the client.**
5. Verify postconditions atomically in same transaction; schema and privilege drift aborts.

**Staging-only test:** `supabase/local_qa/test_issue29_ledger_acl.sql` runs in a transaction and ROLLBACKs all synthetic A/B account fixtures. Tests credential-scoped SELECT, INSERT, duplicate UUID no-op, UPDATE/DELETE denial, goal DELETE denial, legitimate goal edit, cross-account denial, and admin whole-account data erasure. Never run this on production because it temporarily creates Auth rows.

**Emergency rollback (separate, review-only):** `supabase/proposals/issue_29_immutable_contribution_acl_ROLLBACK_ONLY.sql`. The rollback reopens the old security exposure; use only under reviewed incident procedure.

## Gates before any live migration

- Use a disposable staging project with equivalent Auth/PK/FK/RLS. Independent security reviewer approves exact SQL, staged backup, rollback, app version compatibility and two signed-in clients.
- **No direct production change in this PR.** Staging QA and rollback/erasure tests must pass before requesting final migration approval. This proposal must not automatically deploy via CD.
- **Still missing:** server confirmation of mismatched same-UUID receipts; server-authoritative CAS/revisioned goal metadata; conflict UX for two iPhones; append-only correction/money-out events (#16/#42); cloud authoritative achievements and XP reconciliation; real-device QA. These remain explicit release blockers.
- Current client goal metadata uses UPSERT without revision. Revoking direct goal UPDATE would break active behavior, so that is a **separate planned versioned CAS migration**, not attempted here.
