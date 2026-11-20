# Pipo password recovery — P0 implementation and acceptance

Tracks [#33](https://github.com/muhammadihsan-byte/pipo-gamification/issues/33).

## Implemented in this branch
- Email/password sign-in shows **Forgot Password?** with required email validation.
- Request a Supabase password-reset message without revealing whether an account exists.
- Use a dedicated recovery callback `pipo://login-callback/reset-password`, separate from ordinary sign-in `pipo://login-callback`.
- Accept auth callback URLs only when their **scheme, host and path** match the configured callback; reject lookalike hosts.
- Open a non-swipe-dismissable change-password sheet after a verified callback/session exchange.
- Require 8+ characters and confirmation; update via authenticated Supabase Auth, then sign out so the next sign-in uses the new password.
- On Cancel, sign out of the short-lived recovery session before returning to sign-in.
- Add static callback routing and spoofed-host regression tests.

## External configuration — REQUIRED before claiming this works end-to-end

Supabase Dashboard → Authentication → URL Configuration → Redirect URLs must explicitly allow both:
- `pipo://login-callback`
- `pipo://login-callback/reset-password`

Verify the password recovery email template retains `{{ .ConfirmationURL }}` (or equivalent verified token/code redirect). Do **not** commit keys or privileged secrets. Confirm app Info.plist registers the `pipo` URL scheme. Confirm email sending and rate limits are suitable before live release.

## End-to-end acceptance to execute with a genuine test account

1. Create and email-confirm a disposable test user on the connected Pipo project.
2. Sign out; enter its address and choose Forgot Password; request a link.
3. Open the email on a signed iPhone with Pipo installed, including a cold-start scenario.
4. Verify the app opens a dedicated password editor, not an unrestricted dashboard.
5. Verify wrong/missing confirmation is rejected locally and a valid new password succeeds.
6. Verify the user must sign in with the **new** password; the old password no longer works.
7. Test expired or replayed links, cancellation/signout, rate limiting, incorrect email address, app offline, app background/foreground.
8. Test that `pipo://login-callback.evil`, an unrelated host and an ordinary OAuth callback cannot open the reset screen.
9. Verify no account A data is displayed while account B recovers a password; widget/SwiftData ownership stays account-scoped.

## Not delivered by this PR
- Supabase dashboard redirect URL changes or actual outgoing email proof.
- Signed iPhone / physical-device recovery test.
- In-app account deletion, Sign in with Apple authorization revocation, Google/Apple provider setup or privacy policy.
- No StoreKit enablement; no TestFlight; no app submission.

Do not mark #33 or the release gate #8 complete on the strength of this source-only implementation.
