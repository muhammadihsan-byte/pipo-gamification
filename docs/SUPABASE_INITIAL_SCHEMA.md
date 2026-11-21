# Pipo Supabase schema — applied initial migration

**Project:** `pipo` (`jdboaaiiwkblxvejnhol`, ap-southeast-1)
**Applied migration:** `20261120052238_pipo_initial_account_scoped_savings_and_server_owned_entitlements.sql`
**Status:** Applied in Supabase on 20 November 2026, tracked here for GitHub review. This PR **does not execute SQL**; the backend migration was explicitly authorized and completed already.

## Database controls

- `public.saving_goals`: account-owned **self-reported** goal metadata; auth user FK and individual select/insert/update/delete RLS.
- `public.saving_transactions`: account-owned self-reported entries. Composite `(goal_id,user_id)` FK makes it impossible to attach transactions to another account's goal, even with a forged UUID.
- `public.user_profiles`: **server-owned purchased personal/group slot counts**. Only `SELECT` for `authenticated` with owner-only RLS; anonymous users cannot read, and clients cannot write.
- Private `private.pipo_seed_profile()` trigger seeds an all-zero profile on Auth signup. Its EXECUTE privilege is not granted to client roles.
- No banking, money transfers, third-party account access, group invitation authorization, premium billing verification, or real cross-device goal sync is delivered by this migration.

## Verified after application

- Three `public` tables exist with RLS enabled.
- Nine owner-only policies exist; updates use both `USING` and `WITH CHECK`.
- Authenticated role can read but cannot insert, update, or delete `user_profiles`; `anon` cannot read.
- Signup trigger installed; private function cannot be executed by `anon` or `authenticated`.
- Composite goal/owner FK and amount constraints verified in PostgreSQL catalogs.
- Supabase Security Advisor returns no findings. This **does not replace real account testing**.
- There were zero Auth users during initial audit, so authenticated A/B denial tests have **not** been performed.

## Important integration blockers — do not publish yet

1. Current SwiftUI `SupabaseService.syncTransactions` attempts to upsert transactions without first syncing the remote goal: foreign key rejection is **expected**. A separate unmerged PR must add goal-first sync and offline queue retry.
2. Existing `SupabaseService.syncUserProfile` attempts a client-side paid-slot `upsert`, deliberately forbidden by the new table permissions. Disable/rework that client write path before enabling live billing.
3. Paid entitlement grants require Apple-verified **server-side** transaction processing and restricted privileged backend access. See [P0 #28](https://github.com/muhammadihsan-byte/pipo-gamification/issues/28).
4. Only personal goals are represented here. Native group planning currently has no verified membership/invitations; do not falsely imply sharing or transfers.
5. Account deletion UI, privacy policy, Supabase Auth callback URL `pipo://login-callback`, Apple signing, StoreKit sandbox and physical-device tests remain release gates in [#8](https://github.com/muhammadihsan-byte/pipo-gamification/issues/8).
6. Do not import or assign historical `ownerUserID == nil` records to whoever logs in next; verify ownership and obtain consent before migration.

## Next verification

Run `supabase/tests/initial_rls_audit.sql` read-only in the approved Supabase project, then use **two disposable Auth test accounts** through real authenticated SDK/API sessions to check A/B SELECT/INSERT/UPDATE/DELETE denials, goal spoofing, foreign key failures, and sign-out. No fake production financial records or paid entitlements should be created.

**Related:** [#29](https://github.com/muhammadihsan-byte/pipo-gamification/issues/29) · [#13](https://github.com/muhammadihsan-byte/pipo-gamification/issues/13) · [#28](https://github.com/muhammadihsan-byte/pipo-gamification/issues/28).
