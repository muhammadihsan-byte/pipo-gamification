# Account-scoped local data policy (Issue #13)

## What changes

- New personal and group goals store the authenticated account's UUID in `PersonalGoal.ownerUserID`.
- Every dashboard list, personal/group detail route, saving action, history summary, quota count, background transaction sync and widget deep link must check the goal owner against the active authenticated account.
- A saving transaction must match **both** the active account and the owner of its referenced goal. Orphans, mismatched goal IDs and `nil` account IDs are excluded.
- `UserProfile.existing(for:in:)` returns only an **exact** account match. XP, badges, saving counts and purchased slot balances from ownerless historical profiles must not transfer to a new account.
- Account switches clear pending routes, in-app celebrations and widget snapshots. A widget snapshot can load only when its owner UUID matches the active App Group account UUID.

## Migration and legacy-data quarantine

`ownerUserID` is an **optional** persisted property to allow older SwiftData goals to remain in the device store during an additive model change. An existing goal with `ownerUserID == nil` has **unknown provenance**. Never automatically assign it to the next account to sign in. It must remain hidden, not deleted, and never contribute to another user's progress, quota, XP or remote sync. The same policy applies to legacy ownerless transactions and profiles.

**Recovery is deliberately not automatic.** Any later import/recovery UI must verify identity and require explicit user approval, and must preserve an audit record of the decision. On shared devices, simply knowing that a record exists locally is not proof of ownership.

A real **pre-upgrade persisted SwiftData migration** still needs validation on a signed physical device or a simulator seeded with the previous released app schema. Current tests verify in-memory persistence/isolation and quarantine logic, not a full legacy-binary migration.

## Offline and reinstall boundary

- Pipo currently syncs recorded transactions to Supabase but does not provide a complete remote goal restore/backup mechanism.
- **Uninstalling the app may erase unsynced local goals and records.** This issue does not claim cross-device restore or uninstall recovery.
- Supabase authentication/row policies and offline account switching must still be proven against real accounts before public release, tracked by release readiness issue #8.

## Verification gates

- Two-account account-switch fixture, mismatched transactions, orphaned goals and profiles.
- Widget snapshot saved for account A must disappear when account B becomes active or after sign-out; legacy widget snapshots without an owner must be unreadable.
- Deferred saving confirmation and widget deep links must not allow cross-account access.
- Stale async subscription restoration must not alter the new account's state.
- Controlled iOS CI on this branch. **No merge or TestFlight without owner approval.**

**Related:** [Master roadmap #25](https://github.com/muhammadihsan-byte/pipo-gamification/issues/25), [Release readiness #8](https://github.com/muhammadihsan-byte/pipo-gamification/issues/8).
