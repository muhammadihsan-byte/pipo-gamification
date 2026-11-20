# Pipo P0 — Live authentication and signed-iPhone acceptance

**Evidence level:** This document distinguishes repository/simulator tests, live *unauthenticated* API checks, and real signed-device/credentialed acceptance. They are not interchangeable. No real customer account may be used for destructive testing.

## Current source and backend facts (20 Nov 2026)
- GitHub iOS development baseline includes password recovery, sign out, account deletion and disabled social login.
- Connected Supabase project: `jdboaaiiwkblxvejnhol`, Singapore region.
- `delete-account` Edge Function version 1 is deployed and ACTIVE with `verify_jwt=true`; its handler verifies the Auth user before admin deletion, fails closed for Apple-linked identities.
- RLS policies on personal saving tables restrict authenticated users to `auth.uid() = user_id`; the `user_profiles` table is owner-read-only.
- Existing Supabase backend showed zero Auth users at the last read-only audit. There is no available authorized account A/B session or email inbox to complete real user tests in this connected environment.
- Xcode has the correct public project URL/publishable API key and `pipo://` URL scheme; real signing team and provisioning remain unverified.

## 1. Configure Supabase Auth redirect URLs (external dashboard access required)

Open [Pipo Auth URL Configuration](https://supabase.com/dashboard/project/jdboaaiiwkblxvejnhol/auth/url-configuration).

Redirect URLs MUST contain these exact two entries:
- `pipo://login-callback` — ordinary email-confirmation/sign-in callback
- `pipo://login-callback/reset-password` — password-recovery callback

Do **not** substitute only `pipo://login-callback/*` or treat `SUPABASE_REDIRECT_URL` in Xcode as automatic Auth allowlisting. Verify the correct Site URL for the production website after it is actually hosted. Inspect the email-confirmation and password-recovery templates under Authentication → Email Templates, retaining a valid `{{ .ConfirmationURL }}` or provider-approved recovery-link configuration, without exposing any token. Verify SMTP sender, rate limits, spam delivery and expired-link handling. Record a redacted screenshot of both redirect entries and template confirmation.

**Status: NOT VERIFIED.** The connected Supabase management API does not expose an Auth redirect-configuration update/read action; this step is not silently completed.

## 2. Safe remote network smoke and exact evidence

Run [Live Supabase Auth Smoke](../.github/workflows/live-auth-smoke.yml) against the Pipo project. It only reads public config from `Pipo.xcodeproj/project.pbxproj`. It sends:
- unauthenticated and intentionally forged JWT POST calls to the deployed deletion endpoint; both must return HTTP 401/403,
- anonymous GET calls to each private Pipo table; all must return HTTP 401/403,
- anonymous GET to the public GoTrue settings route; must return HTTP 200.

Artifact `pipo-live-anonymous-auth-<run-id>` contains JSON with individual HTTP statuses and a conspicuous NOT_VERIFIED list. No account is created, modified or deleted. Successful anonymous negative tests **cannot** prove valid signed-in sessions, Auth email delivery, or RLS cross-account authorization.

## 3. Real account A/B test (only controlled, disposable identities)

Use **two inboxes you control** and distinct new disposable email/password accounts (A and B). Never use production customers, staff personal accounts or manually inserted `auth.users` rows. Record exact test account UUIDs privately without committing credentials.

- [ ] A signs up, confirms email, signs in on a signed iPhone. B signs up, confirms email, signs in separately. Both use the actual production Supabase project.
- [ ] A creates a personal goal + saving transaction; verify A owns its remote `saving_goals` and `saving_transactions` rows.
- [ ] A signs out in Profile; B signs in. B sees none of A's local goals, transactions, XP, widget or nickname.
- [ ] As B, attempt `SELECT` A goal UUID and cross-owner `INSERT/UPDATE`. Confirm denied/0 rows. B's own goal still works. Never change arbitrary real rows.
- [ ] Forgot Password for A sends a genuine email. Open via a signed iPhone **cold start and warm start**. Recovery goes to a password editor, not the dashboard. Confirm mismatch rejected; new password works; old password fails.
- [ ] Expired/replayed links, wrong email, offline, app termination and account-switch attempts must fail safely. Try an invalid recovery URL, unrelated scheme/host and normal sign-in callback; none may open the recovery editor without a valid flow.
- [ ] While A has valid user data, open Profile → Delete my account. Confirm default deletion CTA disabled; typing anything except `DELETE` cannot submit; Cancel leaves everything intact. Restart without deletion and verify A still exists.
- [ ] ONLY with authorized disposable A, type `DELETE`, submit, and verify the actual A account is removed, A's linked remote rows have cascaded away and its local data/widget is cleared. A cannot sign in with either password afterward.
- [ ] Verify B remains present and can still sign in and see its **own** saving goal; A's previous access token cannot recover deleted private data.
- [ ] Confirm accurate error and local-data preservation for offline, 401, 500 and lost-response cases (use an isolated testing environment; **do not deliberately damage production**). Specifically note the current pending-local-cleanup acknowledgement limitation.
- [ ] Test account with **zero goals** can find the Profile deletion entry and complete deletion.
- [ ] When done, delete the remaining disposable B via the same verified in-app process; independently verify no disposable users or rows remain.

**Status: NOT VERIFIED.** Valid A/B Auth sessions and signed real-device access have not been supplied or established.

## 4. Physical Apple-signed iPhone evidence

With a legitimate Apple Developer team:
- [ ] Confirm Bundle IDs `com.pipo.app`, `com.pipo.app.widget` and App Group `group.com.pipo.app` exist and profiles include correct entitlements.
- [ ] Install a signed build on a physical iPhone; verify signed app/extension entitlements using provisioning, not a simulator-only unsigned build.
- [ ] Test onboarding, optional widget, no-goal Profile, Goal creation, saving history, relaunch, cold-start auth link, keyboard avoidance, small iPhone screen, background→foreground, offline→online and delete/sign-out.
- [ ] Test VoiceOver, Dynamic Type, Reduce Motion, contrast, calendar navigation, permissions and optional photo picker.
- [ ] Confirm group plans are labeled **local only** with no real invitations claimed; personal saving upload is **not** represented as full cloud restore.
- [ ] Verify app has no enabled IAP purchase flow until trusted Apple purchase verification is ready.

**Status: NOT VERIFIED.** CI uses `CODE_SIGNING_ALLOWED=NO` and cannot substitute for signed-device testing.

## 5. App Store publication checklist

- [ ] Approve and host a real Privacy Policy and Support URL, using the legal entity's verified name, privacy contact, collection/retention details and any required local privacy-law disclosures.
- [ ] Configure exact App Privacy answers for Supabase Auth, self-reported savings and any analytics/SDKs.
- [ ] Confirm screenshots, demo credentials/notes, age rating, category, marketing claims and app icon in App Store Connect.
- [ ] If Apple/Google login is later enabled, implement and verify Sign in with Apple token revocation on deletion *before* accepting Apple-linked users.
- [ ] Obtain explicit separate approval before any TestFlight upload or App Store submission.

**Exit criterion:** a green CI is *not* release readiness. Keep [release issue #8](https://github.com/muhammadihsan-byte/pipo-gamification/issues/8) and [auth issue #33](https://github.com/muhammadihsan-byte/pipo-gamification/issues/33) open until signed and live evidence is attached and reviewed.
