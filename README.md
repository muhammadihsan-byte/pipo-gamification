# Pipo

Native iOS starter for Pipo, an offline-first gamified savings app.

## Requirements

- Xcode with the iOS 17 SDK or later
- Swift 6

## Getting started

Open `Pipo.xcodeproj` in Xcode and build or run the shared `Pipo` scheme. The app target includes the Swift sources and `Assets.xcassets`, and supports iOS 17 or later. Run the `PipoTests` unit-test target through the scheme to verify the SwiftData goal model. `PipoApp` configures a local SwiftData container for the goal, sub-item, transaction, and profile models.

The WidgetKit extension supports small and medium widgets. The app shares its widget snapshot with the extension using the `group.com.pipo.app` App Group and refreshes widget timelines after a saved deposit. Register `com.pipo.app` and `com.pipo.app.widget` for signing, and enable `group.com.pipo.app` for both App IDs. The medium widget's “Log deposit” action uses `pipo://log-deposit` to open the selected active personal goal in the app.

The project resolves the Rive iOS runtime through Swift Package Manager. To display the animated mascot, add `pipo_mascot.riv` to the app bundle with the `PipoState` state machine and numeric `animState` input; until that asset is provided, the mascot view uses the existing static artwork.

Supabase uses the Swift SDK through Swift Package Manager. Set `SUPABASE_URL` and `SUPABASE_ANON_KEY` as Xcode build settings or pass them to `xcodebuild`; never use a service-role key in the app. OAuth and email confirmation redirect to `pipo://login-callback`, which must also be allow-listed in Supabase Auth. Transaction sync upserts `saving_transactions` rows with `id`, `goal_id`, `user_id`, `amount`, `xp_earned`, and `date`; enable row-level security and restrict reads/writes to `auth.uid() = user_id`. Group progress uses private Realtime broadcast topics named `group-goal:<goal UUID>`; configure `realtime.messages` policies to authorize only members of the corresponding group before enabling broadcasts.

Purchased slot balances sync through a `user_profiles` table with `user_id` (the `auth.users.id` primary key), `purchased_personal_slots`, and `purchased_group_slots`. Enable row-level security and allow authenticated users to select, insert, and update only rows where `auth.uid() = user_id`. StoreKit uses the repeatable consumable product `com.pipo.goalslot`; each verified purchase permanently adds one slot to the selected personal or group balance. Since Apple does not restore consumable transactions, balances are restored across devices from `user_profiles`. Client-side purchase verification and row ownership policies are not a server-side billing authority; for production, validate signed transactions in a trusted backend before treating synced slot counts as authoritative. The shared Xcode scheme uses [StoreKit.storekit](./StoreKit.storekit) for the $2.00 Simulator product; configure the same product ID as a consumable in App Store Connect for release.

The starter includes Supabase email/password and Apple/Google OAuth authentication, goal creation, savings-rhythm, group-review, and consistency-milestone screens with SwiftUI previews and mock data, plus a starter dashboard and SwiftData models. Group plans support invitation states, equal target splits, and accepted-member sub-contributions. The free tier includes one personal and one group goal slot; additional permanent slots are priced at $2, with no duration restrictions. Goal limits are checked at final plan confirmation, and the paywall uses neutral pricing and cancellation copy. Recording a saving for an existing goal persists a transaction, awards 300 XP, and updates the profile level and rhythm-based streak; levels advance every 1,500 XP. Supabase authentication, transaction sync, and Realtime broadcasts require project configuration and matching database policies.
