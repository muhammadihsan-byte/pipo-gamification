# Pipo P0 — In-app account deletion acceptance

**Source PR:** P0 #33 (this branch). This is a development implementation, **not a release approval**.

## What is implemented

- Profile → Account & privacy → Delete my account, reachable even with **zero goals**.
- Explains irreversible deletion, self-recorded money, and removal of cloud and local data.
- User must type `DELETE` and confirm. Cancel remains available and does not call the server.
- Swift app invokes authenticated `delete-account` Edge Function; it sends only the signed-in ID as a non-authoritative \`expected_user_id\` consistency check; it carries no service-role key or password. The server verifies the caller independently and rejects mismatches.
- Function validates the bearer token against Supabase Auth `/auth/v1/user` and uses the **returned verified ID only** with the privileged hard-delete endpoint.
- Current deployed schema's `saving_goals`, `saving_transactions` and `user_profiles` all reference `auth.users` with `ON DELETE CASCADE` (verified read-only 20 Nov 2026). No new migration is required.
- Local SwiftData goals/entries/profiles are deleted **only after a positive server reply**, restricted to exactly that UUID; `PersonalGoal.subItems` cascade via SwiftData.
- Account-scoped onboarding preferences are removed, app's navigation/entitlements/auth state are cleared and widget snapshots are invalidated.
- Legacy ownerless rows remain quarantined: do **not** claim they belong to the deleting user. They require a separate identity-verified legacy data resolution.
- If local SwiftData cleanup fails after the server succeeds, persist the server-confirmed deleted UUID and retry only that account's cleanup on next launch.

## Backend deployment — COMPLETE; live user acceptance still OPEN

The function is deployed as **version 1, ACTIVE, JWT verification on** in Supabase project `jdboaaiiwkblxvejnhol`. It was inspected after deployment and passed its unit security suite. This does **not** establish that authenticated A/B deletion, session invalidation or remote cascading have been tested on a real account.

- Function name: `delete-account`
- Entrypoint: `index.ts`
- Keep `verify_jwt = true` (see `supabase/config.toml`). The platform validates the caller's user JWT; the function then fetches the actual user using that token.
- Uses the runtime's `SUPABASE_URL`, `SUPABASE_ANON_KEY` and `SUPABASE_SERVICE_ROLE_KEY` **only server-side**; never add privileged values to Xcode, commit them or send them to the client.
- Only `POST`; the request's \`expected_user_id\` must match the verified session UUID, but never selects the deletion subject. Return success only after the Auth admin deletion request succeeds.
- Run Deno unit tests with `deno test supabase/functions/delete-account/handler.test.ts`. Test missing/expired token, cross-user injection, stale-account mismatch, missing confirmation, admin errors and missing server key.
- Confirm no other future tables, storage objects, group memberships or purchase ledgers introduce FK dependencies before deployment.
- Apple Sign in linked accounts require a **verified Apple token revocation process** as part of deletion. The hardened backend explicitly rejects Apple-linked users (HTTP 409) instead of deleting Auth identity without revocation, and social-login entry points are disabled. Re-enable Apple signup only after token revocation is supported and tested.

## Live acceptance before App Store / TestFlight

Use only disposable accounts with explicit test consent. Never delete a real customer's account during QA.

- [ ] Source iOS CI and Deno adversarial tests pass on the **exact** PR head.
- [x] Backend version 1 deployed with `verify_jwt=true` (20 Nov 2026).
- [ ] On a signed iPhone, sign up test account A, save personal and group plans, create a transaction and onboarding nickname; then verify the profile delete entry is reachable.
- [ ] On a brand-new account with **no goals**, verify Profile → Delete account works.
- [ ] Cancel and incorrect confirmation produce zero network deletion calls; a stale confirmation for account A cannot delete a now-active account B.
- [ ] Simulated offline/500/401 backend response leaves A's SwiftData, onboarding and widget state intact and gives truthful failure.
- [ ] Confirm A's Auth user no longer exists, A's cloud goal/transaction/profile rows are gone, refresh tokens cannot access the deleted account, and a later sign-in with A fails.
- [ ] Confirm B's cloud and device rows remain intact after deleting A; ownerless historical local records are never re-assigned.
- [ ] After confirmed deletion, A's local goals, saving transactions, achievements, personalization and widget snapshots disappear; app routes to sign-in.
- [ ] Test network response loss, app force-close after server success, retry-pending cleanup, and repeated deletion attempts. Confirm all responses are truthful.
- [ ] Signed iPhone test with Apple or Google sign-in if enabled; revoke Sign in with Apple tokens/authorization, verify no unauthorized provider retention.
- [ ] Validate actual privacy policy, refund/purchase handling, account-retention statements and App Review support URL.
- [ ] Confirm released group and photo features have appropriate corresponding deletion coverage; do not claim cross-device group removal while group is local-only.

## Release and merge boundaries

- PR #35 and PR #36 are merged into `main`, and PR #34 was superseded instead of force-merged.
- The account-deletion Edge Function is deployed but **still not verified with a real disposable Auth account**. No customer deletion or TestFlight/App Store submission was performed as part of this QA work.
- See `docs/LIVE_AUTH_DEVICE_QA.md` for missing two-account and signed iPhone acceptance evidence. Do not close the P0 release gate until it is collected.
