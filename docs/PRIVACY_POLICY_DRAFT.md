# Pipo Privacy Policy — WORKING DRAFT (not approved / not hosted)

This is a factual drafting aid for product review. Do not publish without confirming the implemented app, SDKs, retention periods, contact address, privacy jurisdiction, and final policy with an appropriate reviewer.

**Last reviewed:** 20 November 2026

Pipo helps people plan self-reported savings goals. Pipo is not a bank, does not hold funds, and does not move money.

### Data you provide
If you register, Pipo processes your email address and authentication identifiers. It also stores the goal names, target amounts, dates and savings entries you record, plus your optional nickname and onboarding preferences. Selected goal images may be saved on your device. Pipo uses this information to show your plans and calculate progress, habits and achievements.

### Where information is stored
The iOS app stores goal, transaction and achievement data in local device storage. It can upload **personal** goals and saving entries to the account-scoped Supabase backend. Group plans and other features may remain local-only. Pipo does not currently provide guaranteed full cross-device restore or backup. Widget data may be temporarily stored in an iOS App Group accessible to Pipo's widget.

### Authentication and sharing
Pipo uses Supabase Auth for email/password sign-in, password reset and session management. Only authenticated accounts should access their corresponding server data through account ownership policies. Social sign-in is disabled in the current release baseline. No claim is made that Pipo connects to real bank balances or financial institutions.

### Account deletion
From Profile → Account & privacy → Delete my account, a signed-in user can request permanent deletion. Confirmed server deletion removes the Auth account and cascades to the account's saved server goals/entries/profile. The app also erases matching local account data, onboarding preferences and widget state. Some historical ownerless legacy device records cannot be safely assigned to or removed on behalf of an account without verification; this requires a separate cleanup process. Specify applicable legal-retention exceptions and timelines before publication.

### Data security, retention and rights
The app uses HTTPS for Supabase traffic, and restricts backend records to the authenticated account through RLS. This is not a guarantee of absolute security. Any data-retention periods, breach contact, access/correction requests, privacy requests, analytics and SDK tracking need review and verification.

### Contact and jurisdiction — REQUIRED BEFORE PUBLICATION
Add the approved privacy contact email, the legal operator/business name, governing jurisdiction, data-controller details, effective date and public URL. Confirm supplier and analytics disclosures and applicable Indonesia/privacy law with the owner.

**Publishing gate:** A public policy URL and App Store Connect App Privacy declarations require separate verification.
