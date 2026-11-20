# Pipo iOS — App Store release gates (20 November 2026)

**Scope:** iOS-only gamified, self-reported saving planner. Pipo does not hold, transfer, or access real money. No financial service or interest claim should be made. **Do not submit until all required gates are evidenced.**

## Verified in repository / backend
- SwiftData local saving flow; owned account records are isolated.
- Supabase Auth login and password recovery source; separate callback routes.
- In-app Delete Account flow with typed confirmation, app-owned local cleanup and backend Auth-user hard-delete handler. Cloud tables currently have ON DELETE CASCADE FKs.
- Remote personal saving **upload only**: no cross-device restore, conflict resolution, or reinstall guarantee. Do not call it full backup or full sync.
- Group plans are device-local rather than real multi-user shared accounts; avoid marketing collaboration as shipped.
- StoreKit purchases are explicitly disabled until server-side Apple verification and ledger restoration exist. No money should be collected through unfinished purchase flow.
- Social sign-in UI and SDK entry path are disabled until Apple/Google credentials and Apple authorization revocation are complete.

## Must complete before release
- [ ] Deploy and verify signed JWT-protected `delete-account` Edge Function, including legitimate disposable-user hard deletion, session invalidation, owner-isolated row cascade and account switch. Apple-linked user accounts must remain deletion-blocked while Apple revocation is unfinished.
- [ ] Supabase Auth callback redirect allowlist, email templates and disposable-account live password-reset acceptance.
- [ ] Physical signed iPhone review of signup, onboarding, goals, restore after reinstall, widget/deep links, accessibility, keyboard, background/foreground, offline and zero-goals profile.
- [ ] Implement verified remote download/restoration, or clearly explain device-local-only limitations and ensure no misleading "backed up" promise in UX/marketing.
- [ ] Apple Developer enrollment, signing certificates/provisioning, unique Bundle ID, actual archive/export and store configuration; validate Info.plist permission keys and privacy manifests for all bundled SDKs.
- [ ] Write, approve and host a **public Pipo privacy policy** URL and support/contact URL; configure them in App Store Connect. Verify retention, deletion exclusions, photo and nickname handling, security, analytics, contact.
- [ ] Submit accurate App Privacy questionnaire (email, account ID, self-reported saving records and linked identifiers, and SDK data); review SDK privacy manifests/required-reason APIs.
- [ ] App Store Connect listing: screenshots from signed real build, demo test account/notes for review, app description (no financial custody claims), app category, age rating, rights, target regions.
- [ ] Decide whether paywall must be hidden or completed; any future StoreKit sales require trusted transaction verification, entitlement restoration and clear purchase disclosures (#28). A disabled purchase button that looks live is not a valid release payment experience.
- [ ] If social login is enabled later: native Apple/Google OAuth QA, equivalent sign-in under 4.8, and **Sign in with Apple token revocation upon deletion**. Apple linked accounts are deliberately blocked from destructive hard delete pending implementation; do not enable Apple signup before this resolves.
- [ ] Perform final release build, release certificate and entitlement audit, approved privacy review and Apple submission explicitly.

## Official Apple requirements (checked 20 Nov 2026)
- App Review Guidelines: https://developer.apple.com/app-store/review/guidelines/
- App account deletion: https://developer.apple.com/go/?id=ar-ad-support
- Human Interface Guidelines account management: https://developer.apple.com/design/human-interface-guidelines/managing-accounts
- App Privacy Details: https://developer.apple.com/app-store/app-privacy-details/
- App Store Connect privacy settings: https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/

**Evidence principle:** do not close P0 #8 until live tests, signed-device review, external privacy/Apple-account configuration and final human release approval. CI and static inspection do not replace those steps.
