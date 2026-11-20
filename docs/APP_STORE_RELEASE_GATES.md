# Pipo App Store submission gates

This is an acceptance checklist, **not** a guarantee of Apple approval. Review the latest [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) before submission (last reviewed 20 November 2026).

## P0 blockers

- [ ] **Complete, working sign-in for review:** configure Supabase Auth URL redirects, email verification and password reset; validate Google/Apple OAuth if displayed. Provide an active review account or an appropriate fully functional demonstration mode. Never rely on fixed DEBUG fixtures for a production build.
- [ ] **In-app account deletion:** if users can create accounts, provide an in-app deletion path that actually removes the account and its associated personal data (subject to legitimate retention), not a broken link or unsupported promise. If Sign in with Apple is used, address token revocation. See guideline 5.1.1(v).
- [ ] **Purchase compliance:** Pipo's permanent goal slots are digital app features governed by Apple's in-app purchase rules. A `Consumable` for permanent incremental slots needs an authoritative ledger and cross-reinstall entitlement restoration; consider a simpler product structure in App Store Connect. This build deliberately disables checkout until [#28](https://github.com/muhammadihsan-byte/pipo-gamification/issues/28) is resolved.
- [ ] **Privacy policy and disclosures:** provide a live, relevant privacy policy URL, accurate App Privacy declarations, data retention, account deletion details and support contact. Saving records are sensitive personal financial-planning information, even if they are self-reported.
- [ ] **Accurate financial claims:** clearly state Pipo is a saving **planner / motivation tracker**; it does not hold, transfer, verify, invest, or aggregate bank balances. Group invitations and shared progress must not be presented as operational when there is no backend.
- [ ] **Avoid unusable surfaces:** password reset, account deletion, IAP, invite links, reminders and deep links must work before advertising them as features. Remove or explicitly label not-yet-available features, and never charge for unavailable features.
- [ ] **Device quality:** signed install to a real iPhone, app/Widget App Group entitlement, offline/online recovery, dark/light and Dynamic Type, VoiceOver, Reduce Motion, permissions, real navigation, crash checks, multiple iPhone sizes.
- [ ] **Approval and metadata:** Apple Developer bundle IDs, proper provisioning, truthful screenshots/review notes, account access instructions, privacy support URL, export compliance and marketing materials. Do not upload to TestFlight or submit until these pass.

## Review source references

- [Apple App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) (notably 2.1, 3.1, 4.8, and 5.1.1).
- [Apple In-App Purchase guidance](https://developer.apple.com/design/human-interface-guidelines/apple-in-app-purchase).
- [Apple account management guidance](https://developer.apple.com/design/human-interface-guidelines/managing-accounts).
- [Supabase RLS documentation](https://supabase.com/docs/guides/database/postgres/row-level-security).

**Status as of 20 Nov 2026:** Database RLS is deployed, initial goal-first local→cloud sync is under review, and live purchases are disabled. Real account A/B tests, account deletion, backend purchase verification, physical device and App Review materials remain unverified.
