# Pipo password recovery — release-blocker QA

Replaces the integration scope of superseded PR #34; tracks P0 #33.

## Implemented in this branch
- Forgot Password validates a trimmed email address; sends a neutral confirmation.
- Supabase reset email uses `pipo://login-callback/reset-password`; normal email confirmation uses `pipo://login-callback`.
- Callback matcher validates scheme, host and path and rejects lookalike hosts.
- A password-recovery callback uses PKCE session exchange and quarantines that recovery session from dashboard and syncing.
- Password editor requires 8+ characters and matching entries; non-swipe-dismissable until success or signout.
- Successful password change signs out and requires a fresh login. Cancellation also signs out.
- Social OAuth UI is hidden and server invocation explicitly disabled until provider configuration and Apple token revocation are complete.

## Required Supabase dashboard configuration (not managed by connected tools)
Go to **Supabase → Authentication → URL Configuration → Redirect URLs**:
- `pipo://login-callback`
- `pipo://login-callback/reset-password`

Keep the password-recovery email template's verified confirmation link. Verify real email delivery, expiry, throttling, and configured Supabase Auth redirect allowlist.

## Live device acceptance — not yet proven
- [ ] Create/confirm *disposable* account with email.
- [ ] Trigger forgot-password email; open on a signed iPhone, including terminated/cold-start app.
- [ ] Check only the secure password editor appears, never Home; cancel returns to unauthenticated sign-in.
- [ ] Confirm new password works, old one fails; expired/reused links fail safely.
- [ ] Test no-account email, wrong email, offline/invalid link and rate limits.
- [ ] Test account A/B switching; widgets and SwiftData stay owner-scoped.
- [x] `pipo` callback scheme is present in the Xcode project `Info.plist` (static source verified).
- [ ] Confirm the callback works in an Apple-signed build on a real device.
- [ ] Confirm email templates do not redirect to a staging URL.

CI passing proves Swift source builds and unit tests only. It does NOT prove email or live Supabase Auth settings work. Never claim password recovery fully accepted until these checks pass.


**Automated but non-destructive regression:** PR #37 includes iOS simulator checks for the Forgot Password entry and account deletion confirmation, plus a live anonymous-denial probe. The real email inbox and production Auth redirect allowlist require separate dashboard/device evidence; see `docs/LIVE_AUTH_DEVICE_QA.md`.
