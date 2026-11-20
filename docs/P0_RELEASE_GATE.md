# Pipo P0 release-readiness gate

Tracks GitHub Issues #8 and #13, alongside #14 and #15, in one development PR.

## What the PR can prove
- [x] Static bundle IDs, App Group declarations, Info.plist callback, StoreKit local product and approved badge presence via scripts/check-p0-release-config.sh.
- [ ] iOS build + unit suite against the exact PR head.
- [ ] Controlled native Dashboard B + badge gallery UI simulator test and MP4.
- [x] No code-signing, upload, deployment or TestFlight steps are run by this PR.

## External, release-blocking checks — require authorized access
- [ ] Apple Developer: verify bundle IDs com.pipo.app and com.pipo.app.widget; App Group group.com.pipo.app; correct team and provisioning for both app and extension.
- [ ] Sign and install a real iPhone archive; verify widget entitlement. Simulator CI with CODE_SIGNING_ALLOWED=NO does NOT test signing.
- [ ] Configure legitimate SUPABASE_URL, publishable/anon key and pipo://login-callback allowlist. Never commit service-role keys.
- [ ] Test signup, email confirmation, OAuth if enabled, logout, expired session and re-login for two accounts and offline-to-online transitions.
- [ ] Verify real Supabase row-level security with account A and B: no cross-account SELECT, INSERT or UPDATE on saving_transactions or user_profiles. Deny private group realtime subscriptions to non-members; group membership is not implemented yet.
- [ ] Verify com.pipo.goalslot StoreKit product in App Store Connect sandbox. Test purchase, cancellation, pending, replay and cross-account restoration. A trusted backend must validate signed transactions before remote purchased-slot balances are an authoritative production entitlement.
- [ ] Test on actual iPhone devices: goal creation, saving entry, relaunch, calendar, keyboard, photo picker, Dynamic Type, VoiceOver, Reduce Motion, widget deep links and signed-in/out state.
- [ ] Legacy ownerless rows: prove a persisted SwiftData upgrade from a previous binary, not only in-memory tests. Never auto-claim unknown-owner historical records; identity-verified, opt-in recovery is a separate authorization step.
- [ ] Decide whether prior com.example.SatuSaku installation needs user-assisted migration. Different bundle IDs do not share sandbox data.
- [ ] Provide privacy policy, support route and account deletion before App Store submission.

## Read-only Supabase policy inspection

An authorized administrator should run these without sharing credentials or personal financial records:

    select schemaname, tablename, rowsecurity, forcerowsecurity
    from pg_tables
    where schemaname = 'public'
      and tablename in ('saving_transactions','user_profiles');

    select schemaname, tablename, policyname, cmd, roles, qual, with_check
    from pg_policies
    where (schemaname = 'public' and tablename in ('saving_transactions','user_profiles'))
       or (schemaname = 'realtime' and tablename = 'messages');

Inspect and prove both read filters and INSERT/UPDATE WITH CHECK constraints, usually auth.uid() = user_id, using two real accounts. Merely enabling RLS is not evidence that its policies are correct.

## Physical iPhone acceptance scenarios
1. A creates goals and saves, signs out; B must never see or edit A's goal, transaction history, badge, XP or widget.
2. Switching accounts during a saving sheet, milestone or StoreKit restoration cannot leak data or purchased slot allowances.
3. Offline-to-online and app relaunch preserve private local data and authorized transaction sync.
4. Legacy ownerless saved goals remain safely preserved and hidden, never adopted by the next person who signs in.
5. Daily/weekly/biweekly/monthly/flexible goals show consistent progress. Verify month-end, timezones, missed periods, overrun and repeated saves.
6. One real badge unlock appears after the transaction persists, survives relaunch and is not shown under another account.
7. Local group planning must not claim invitations were delivered or money was moved.

## Explicit limitations
Full cross-device restoration, trusted Apple billing verification, identity-verified historical recovery and real shared group invitations are NOT delivered by this PR. Local unsynced data can be lost on uninstall. No merge, TestFlight or production release without separate explicit approval.
