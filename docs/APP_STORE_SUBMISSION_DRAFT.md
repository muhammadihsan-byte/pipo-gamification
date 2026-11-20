# Pipo iOS — App Store Connect submission copy (DRAFT)

**Not for submission yet.** Replace or verify placeholders in App Store Connect; never invent paid products, connected bank features, cross-device sync or a completed launch date.

## Suggested product metadata

- **App name:** Pipo — Saving Goals
- **Subtitle:** Make your goals a habit
- **Primary language:** English
- **Suggested category for review:** Finance or Lifestyle (choose based on App Store Connect category conventions and final product purpose)
- **Platform:** iPhone/iOS initially
- **Bundle ID:** `com.pipo.app`
- **Widget extension:** `com.pipo.app.widget`
- **Suggested keywords to evaluate:** saving goals, savings tracker, goal planner, habit tracker, money goals, personal planner
- **Support URL candidate:** `https://pipoapp.tech/support` — **NOT verified/live or approved**
- **Privacy URL candidate:** `https://pipoapp.tech/app-privacy` — **NOT verified/live or approved**
- **Marketing website candidate:** `https://pipoapp.tech` — domain public reachability not verified

## App Store description draft

Pipo is a playful place to plan your saving goals and keep track of your progress.

Set a goal for something you care about, choose a pace that works for you, and log the amounts you've saved. Watch your journey grow through progress, streaks and achievements, with Pipo cheering you on along the way.

**Features in the current development baseline**
- Set personal saving goals with targets and dates
- Record contributions yourself — no bank account connection
- See how your plan is progressing
- Follow habits, milestones and achievements
- Plan a group goal locally on your device (no live invitations)
- Add an optional Home Screen widget

**Important:** Pipo is a planning and habit-tracking tool, not a financial institution. It does not hold, transfer, invest or verify money. Saving amounts are entered by you. Some information is stored on the device and full cloud restore is not guaranteed.

**Do not state** that group members can collaboratively join remotely, that bank balances are linked, or that paid extra slots are ready until independently verified.

## App Review notes draft

Pipo uses Supabase email/password authentication. The app supports account deletion under **Profile → Account & privacy → Delete my account** (type DELETE to confirm). Email recovery is available from the sign-in screen. Apple/Google social sign-in is disabled, and paid extra slots are not currently sold. The app does not conduct financial transactions. Group plans in this version are stored locally, with no external member invitations.

**Reviewer test credentials:** [PREPARE VERIFIED EXPIRING DEMO ACCOUNT THROUGH PRIVATE APP STORE CONNECT REVIEW INFORMATION — DO NOT COMMIT CREDENTIALS].

**Additional review information:** [provide signed build steps only if nonstandard, test region and actual recovery inbox]. Do not claim the app is production-ready until real iPhone E2E acceptance is complete.

## App Privacy draft review cues

- Email address and user ID (account login/identification)
- User-entered financial goals, target amounts and savings history (evaluate **Other Financial Info** classification even though Pipo is not a banking app)
- Optional nickname and onboarding settings
- On-device optional images and widget contents
- Supabase vendor authentication/database service, data location, retention and security logs
- Any SDK crash reporting, analytics, tracking or diagnostic collection in the actual signed binary

Make App Privacy answers from the implemented build, **not** from general copy. Record if data is linked to users, used for tracking, retained by vendors, or collected but only processed on device.

## Non-negotiable publication gates

- [ ] Legal operator, privacy contact mailbox, privacy retention policy and public HTTPS URLs verified
- [ ] Signed iPhone build, app/extension identifiers, App Group and Apple entitlements verified
- [ ] Disposable A/B account tests, recovery emails, deletion cascade and local cleanup verified
- [ ] App Review screenshots captured from final signed build at accepted device dimensions
- [ ] Privacy information questionnaire, age rating, content rights, marketing claims and regions reviewed
- [ ] Demo account operational and documented privately for Apple
- [ ] No incomplete StoreKit or social auth pathways exposed
- [ ] Explicit owner approval before TestFlight or App Store publishing

Official Apple requirements: https://developer.apple.com/app-store/review/guidelines/ ; https://developer.apple.com/app-store/app-privacy-details/


## Privacy-manifest implementation and release verification

- App: `Pipo/App/PrivacyInfo.xcprivacy` declares app-owned use of `UserDefaults` and shared App Group preferences using current Apple approved reason codes `CA92.1` and `1C8F.1`; declares app-level email, user ID, self-reported financial goals and related account content processed for app functionality, linked to the account and not for tracking.
- Widget: `Pipo/Widget/PrivacyInfo.xcprivacy` declares App Group `UserDefaults` reason `1C8F.1`, with no independent server collection or tracking claimed.
- `scripts/check-privacy-manifest.sh` validates both plists and verifies the built iOS simulator **Pipo.app** and widget **.appex** each contain their respective manifest. The GitHub Actions job uses the actual compiled bundle paths, not just repo file existence.
- [ ] **Still required:** audit included versions of Supabase Swift, Rive, Lottie and transitive SDKs for their own manifests/signatures and API usage; review the final Xcode privacy report from an Apple-signed archive and cross-check actual App Store Connect App Privacy answers. The native manifest declaration alone does not establish compliance with all Apple SDK privacy requirements.
- Relevant Apple reference: https://developer.apple.com/documentation/bundleresources/privacy-manifest-files
