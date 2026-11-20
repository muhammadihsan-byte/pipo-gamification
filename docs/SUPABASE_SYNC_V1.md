# Pipo iOS → Supabase: safe personal-savings sync (Issue #29)

## Deployed backend

Project: `jdboaaiiwkblxvejnhol` (Singapore).
The approved migration `20261120052238` is deployed. Its exact source is tracked in [draft PR #31](https://github.com/muhammadihsan-byte/pipo-gamification/pull/31). This feature branch does **not** modify the deployed schema.

## Client behavior

1. Authentication uses the **public Supabase publishable key**, never a secret/service-role key. Both Xcode configurations use the approved project's public URL.
2. On personal-goal creation, successful saving, account sign-in/switch, and foreground entry, queue a local-to-cloud sync for **only** the active owner's personal goals and corresponding transactions.
3. For each sync batch, validate goal and transaction ownership, exclude group drafts and orphaned/legacy records, and validate amounts before network I/O.
4. UPSERT `saving_goals` first, then `saving_transactions` by stable UUID. This satisfies the server's composite goal+owner FK. Retries are idempotent by primary key.
5. If the connection fails, the SwiftData entry remains available on that device. Do **not** delete local data or display a successful-cloud-backup claim. A best-effort retry happens on next app foreground or sign-in.
6. SwiftData remains the on-device source of truth. This phase does **not** download goals from Supabase or guarantee data restoration after uninstall, device replacement, concurrent multi-device edits or app deletion. All of those need explicit conflict/recovery design.
7. Only **self-reported savings** are stored: no account balances, transfers, payment processing or banking connection. Group plans and group Realtime are local-only until authenticated group membership exists.

## Payment safety

The initial `user_profiles` table is restricted to owner SELECT. Pipo cannot send a direct client UPSERT to purchased-slot counters. `StoreKitManager.purchasesEnabled` is **false**: users cannot be charged for extra permanent slots before we have verified Apple transactions on a trusted backend with an idempotent ledger, real account binding, and reinstalls/restoration proof. See [#28](https://github.com/muhammadihsan-byte/pipo-gamification/issues/28). Do **not** change database permissions to accommodate the old client.

## Tests included in this PR

- Deployed goal/transaction payload keys, ISO 8601 timestamps, rhythm values.
- Reject another user's goals, ownerless rows, group goals and orphan/cross-account transactions.
- Reject negative/non-finite amounts and invalid goals.
- Purchase action fails before contacting StoreKit while trusted verification is unavailable.

## Manual integration checklist — release blockers

- [ ] Verify Email Auth and exact callback URL `pipo://login-callback` in Supabase Authentication → URL Configuration, including confirmation and reset links.
- [ ] Create **two authorized test accounts** through Supabase Auth (no real customer data); verify account A can create, read and update its own goal and entries; B cannot SELECT/INSERT/UPDATE/DELETE or overwrite A's records.
- [ ] Validate database role/RLS enforcement via actual session tokens, not only administrator SQL checks.
- [ ] Test offline create, sign-out, switch to B, app relaunch, reconnect, and return to A. Verify local and server records cannot leak and no duplicate transaction is created on retry.
- [ ] Test personal-goal recovery from Supabase on a fresh device. Not implemented in this phase.
- [ ] Decide on deletion semantics: account deletion must remove auth and private personal records, revoke sessions/Apple tokens where applicable, and report completion accurately.
- [ ] Run physical iPhone tests and an Apple-signed archive, with StoreKit sandbox only after payment backend is approved.
- [ ] Validate privacy notices, App Store metadata, demo/review credentials and user support details.

No remote SQL, TestFlight, app release or GitHub merge is performed by this PR.
