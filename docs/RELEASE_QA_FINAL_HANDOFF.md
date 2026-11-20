# Pipo iOS — final release QA handoff (20 November 2026)

**Review state:** Auth safety and code validation are in progress, but **App Store readiness is not approved**. Keep [release issue #8](https://github.com/muhammadihsan-byte/pipo-gamification/issues/8) and [Auth issue #33](https://github.com/muhammadihsan-byte/pipo-gamification/issues/33) open.

## Completed / remotely verifiable
- In-app email sign-in, password reset source, account sign-out and typed-confirmation account deletion; social providers disabled.
- Account deletion Supabase function v1 deployed and ACTIVE with JWT verification. Existing unit tests enforce caller-subject verification and fail closed for Apple-linked identities.
- Live anonymous/forged-token security smoke tests passed: deletion rejects 401, all private tables reject anonymous reads 401, public Auth settings 200.
- Database RLS enabled and owner policies inspected; savings rows have cascading foreign keys to auth.users.
- Zero real users currently exist in Supabase project `jdboaaiiwkblxvejnhol`; **no signed-in A/B security proof yet**.
- This PR adds visible in-app data and privacy summary, no-network unit tests for a credentialed two-user QA harness, and a workflow to perform READ-ONLY tests after verified disposable test accounts are available.
- Separate **website PR #5** stages the future app-specific privacy and support pages. They deliberately remain draft/noindex and **not public App Store policy URLs**.

## 1. Authentication redirects — requires Supabase dashboard access

Go to [Authentication → URL Configuration](https://supabase.com/dashboard/project/jdboaaiiwkblxvejnhol/auth/url-configuration). Check and explicitly allowlist:
- `pipo://login-callback` (regular confirmation/sign-in)
- `pipo://login-callback/reset-password` (password recovery)

Go to [Authentication → Email Templates](https://supabase.com/dashboard/project/jdboaaiiwkblxvejnhol/auth/templates). Confirm that signup confirmation and password recovery emails use verified Supabase links, correct custom redirect URL, a sender the test inbox accepts, and no misleading staging URL. Test cold-start and warm-start signed-iPhone deep linking, expired/reused links, sign-out after reset, and old password rejection.

**Not complete.** The connected Supabase management actions do not provide a read/write action for Auth redirect allowlist or hosted email templates. Build settings do not set the server allowlist.

## 2. Read-only two-account RLS test using existing disposable users

Do **not** use real customer, personal primary, or production paid accounts. Create two accounts with email aliases containing `+pipoqa` (for example `name+pipoqa-a@yourdomain.example` and `name+pipoqa-b@yourdomain.example`). Use only an inbox that you explicitly control. Verify the email confirmation messages and sign in on a real app build. Each account must create **its own personal goal and one saving entry**, triggering cloud upload.

In GitHub repository → Settings → Secrets and variables → Actions, set (do **not** commit):
- `PIPO_QA_A_EMAIL`
- `PIPO_QA_A_PASSWORD`
- `PIPO_QA_B_EMAIL`
- `PIPO_QA_B_PASSWORD`

In [GitHub Actions](https://github.com/muhammadihsan-byte/pipo-gamification/actions), manually run **Authenticated RLS QA (Disposable Accounts Only)** with `approve_disposable_accounts=true` **after** confirming the accounts are disposable. It reads the public project URL and publishable key already in the iOS build, obtains each user's JWT, proves each has its own seeded goals/transactions, and checks A cannot SELECT B's rows nor B access A's. It does **not** change or delete any rows. It will fail instead of falsely passing if either account has no cloud data.

- [ ] Both sign-ins and own goal/transaction reads succeed.
- [ ] Cross-account reads are empty and are backed by existing rows.
- [ ] Two-account test evidence review complete; script makes no write-isolation claim. Perform safe write-denial tests with controlled disposable data on a signed device or staging project.
- [ ] Never expose tokens, credentials or emails in issue comments, screenshots or artifacts.

## 3. Authenticated deletion and signed iPhone (not runnable here)

With two controlled disposable accounts, test only after A/B RLS proof:
- [ ] A signs out; B never sees A's local SwiftData, badges, widget or nickname.
- [ ] Verify Profile → Delete my account is reachable with zero goals, Cancel never calls server, and DELETE is required.
- [ ] A initiates deletion through a real authenticated session. Confirm Auth A is gone, A's cloud goals/entries/profile are deleted, and B's still exist; A cannot sign back in.
- [ ] Verify full local cleanup, background/foreground, force-close after response loss and offline/401/5xx behavior. **Known gap:** if Auth deletion succeeds but the response is lost before the device records acknowledgment, leftover owner-scoped local data may remain on disk; do not mark privacy signoff complete until resolved/proven.
- [ ] Verify old access JWT behavior: deletion invalidates refresh sessions, **but existing JWTs can remain valid until expiration**. Ownership FKs and tables should prevent re-creating private deleted-user data; security requirements may need a server-side session existence check.
- [ ] Check Apple's account deletion and sign-in policies. Apple-linked identities currently fail closed because revocation is not implemented and social sign-in is disabled.
- [ ] Ensure no incorrect claim about full cross-device backup or money movement.

**Signing:** Bundle IDs `com.pipo.app` and `com.pipo.app.widget`, App Group `group.com.pipo.app`. CI simulator builds are unsigned and cannot validate Apple Developer Team, provisioning, push capabilities, App Store Connect ownership, or a real widget extension.

## 4. Public policy and App Store submission

- [ ] Review website PR #5 app privacy/support drafts with the verified legal operator and contact details. Confirm website domain `pipoapp.tech` actually resolves and hosting is authorized.
- [ ] Approve privacy contact email and real mailbox; confirm data retention/backup, cross-border processing, vendors, bundled SDK privacy manifests, and app data collection answers.
- [ ] Publish and verify **approved**, indexable public URLs after explicit website launch authorization; update App Store Connect and in-app privacy links when live.
- [ ] Review [App Store submission draft](APP_STORE_SUBMISSION_DRAFT.md), App Privacy disclosures, age rating, regional availability, screenshots, a signed build, and functional reviewer credentials.
- [ ] Verify all StoreKit purchases are disabled unless trustworthy receipt verification and restore is built. Do not enable Apple/Google social providers before their native QA and Apple token revocation.
- [ ] No TestFlight or App Store submission without separate owner authorization.

## Evidence tiers
1. **CI unit tests:** source validation; no live network or signing.
2. **Live anonymous API smoke:** negative authorization, no authenticated A/B proof.
3. **Read-only authenticated A/B harness:** real JWT and READ isolation if disposable credentials are available; not account deletion proof.
4. **Real device destructive acceptance:** actual Auth deletion, cascade, local cleanup, signed code, cold-start email — required before publication.


## Privacy-manifest implementation and release verification

- App: `Pipo/App/PrivacyInfo.xcprivacy` declares app-owned use of `UserDefaults` and shared App Group preferences using current Apple approved reason codes `CA92.1` and `1C8F.1`; declares app-level email, user ID, self-reported financial goals and related account content processed for app functionality, linked to the account and not for tracking.
- Widget: `Pipo/Widget/PrivacyInfo.xcprivacy` declares App Group `UserDefaults` reason `1C8F.1`, with no independent server collection or tracking claimed.
- `scripts/check-privacy-manifest.sh` validates both plists and verifies the built iOS simulator **Pipo.app** and widget **.appex** each contain their respective manifest. The GitHub Actions job uses the actual compiled bundle paths, not just repo file existence.
- [ ] **Still required:** audit included versions of Supabase Swift, Rive, Lottie and transitive SDKs for their own manifests/signatures and API usage; review the final Xcode privacy report from an Apple-signed archive and cross-check actual App Store Connect App Privacy answers. The native manifest declaration alone does not establish compliance with all Apple SDK privacy requirements.
- Relevant Apple reference: https://developer.apple.com/documentation/bundleresources/privacy-manifest-files
