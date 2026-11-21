# Pipo Supabase backend — initial audited state

Project: `jdboaaiiwkblxvejnhol` (Singapore, PostgreSQL 17).
Applied migration: `20261120052238_pipo_initial_account_scoped_savings_and_server_owned_entitlements`.
The migration in `supabase/migrations/` is the exact SQL already applied to this development Supabase project on 20 November 2026.

## Scope
- `saving_goals`: self-reported account-owned goals; authenticated owner can SELECT/INSERT/UPDATE/DELETE.
- `saving_transactions`: self-reported entries; authenticated owner access and a composite `(goal_id, user_id)` foreign key to the corresponding owner's goal.
- `user_profiles`: purchased-slot counters; authenticated owner can **SELECT only**. Zero-balance profile auto-created by protected trigger after auth signup. A trusted purchase ledger does not exist yet.
- All three tables have RLS enabled and owner-based policies. `anon` has no grants. Protected `private.pipo_seed_profile` is not executable by anon/authenticated.
- Group collaboration and group Realtime access are **not** implemented or enabled by this migration.

## Important: SwiftUI integration not yet live
- The existing SwiftUI `SupabaseService.syncTransactions` writes `saving_transactions` but does not first persist goals to `saving_goals`. That will be rejected by the new composite FK until goal-first sync is implemented.
- The existing `SupabaseService.syncUserProfile` client UPSERT to `user_profiles` is intentionally denied. **Do not grant clients write access to paid counters as a workaround.** Disable/reroute client purchase sync through a trusted Apple-verified backend before enabling real purchases. Track [#28](https://github.com/muhammadihsan-byte/pipo-gamification/issues/28).
- Xcode build settings for `SUPABASE_URL` and `SUPABASE_ANON_KEY` are still blank in committed source. Configure the intended environment using a public/publishable key only. Never embed a service-role or secret key in iOS.
- Need complete goal serialization (subitems, group-only metadata and optional photos are intentionally excluded), account A/B authentication integration tests and safe offline-to-online retry strategy.
- Current local legacy ownerless rows remain quarantined; no silent automatic adoption.

## Verification already performed (read-only)
- Confirmed migration installed, three tables with RLS enabled, nine owner policies, no anon grants, no authenticated writes on `user_profiles`, and composite transaction-to-owner FK.
- Confirmed profile creation trigger is in private schema, uses a restricted search_path and is not callable by anon/authenticated.
- Supabase security advisor returned no lints. This is **not** a replacement for two-account real API tests and real device QA.

## Remaining launch gates
- Two signed-in accounts: prove unauthorized SELECT/INSERT/UPDATE/DELETE/UPSERT are denied and cannot spoof `user_id` or `goal_id`.
- Implement goal-first SwiftUI sync and read-only profile restoration without triggering a direct entitlement UPSERT. Keep all changes on separate PRs with explicit owner merge approval.
- Apple Developer signing, Supabase email/OAuth redirect configuration and appropriate Sign in with Apple availability, StoreKit sandbox/server-authoritative purchase verification, account deletion UX, privacy disclosures, physical-device QA, historic SwiftData migration.
- This migration alone does **not** make the app App Store ready or guarantee App Store approval.

Related: [#29](https://github.com/muhammadihsan-byte/pipo-gamification/issues/29), [#28](https://github.com/muhammadihsan-byte/pipo-gamification/issues/28), [#8](https://github.com/muhammadihsan-byte/pipo-gamification/issues/8).

**No app release, TestFlight upload, or GitHub merge was performed by this backend setup.**
