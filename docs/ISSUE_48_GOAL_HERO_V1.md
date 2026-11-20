# Issue #48 — Goal Detail photo hero, native V1

## Implemented
- Based on approved Figma one-photo detail `1022:1194` (393×956, 280pt image below the status region), using a responsive hero capped at 280pt and at least 190pt on compact screens. The existing navigation stack owns the iOS status/safe area.
- Full-width private user photo with top-overlay Goals (back) / Photos (native picker) controls, each at least 44pt. Dark gradient ensures contrast on bright user photos.
- Local-only photo replacement/removal for an account-owned `PersonalGoal`, with rollback if SwiftData save fails and protection against switching accounts during asynchronous media loading.
- Graceful zero-photo state, one real photo without pagination, and a reusable no-autoplay swipe component with an accessible 1/N button for future verified multi-photo data. **The V1 data model only supplies zero or one image.** No fake second photo, no duplicate crop, and no bundled Bali image.
- Photo normalization strips source EXIF/location by decoding and redrawing to a compressed JPEG; rejects empty, unreadable, over-12MB, or over-36MP input; caps longest output dimension at 1600px and JPEG bytes at 1.5MB.
- Goal title, accurate manually recorded amount/target, exactly one progress bar, existing earned badge logic, activity, lifecycle and sticky Record a saving. Uses existing Pipo V4, badge and action design system; does not change monetary records or XP.

## Explicit non-goals
- Multi-photo persistence/upload and Supabase storage migration are **not enabled**. Must separately implement private account-scoped bucket, ordering, deduplication, replace/delete, backup, per-user quotas, expiry/caching, EXIF stripping, and RLS; no new server permissions are added in this PR.
- No artificial progress, bank-linked claims, transfers or new saving history ledger.
- Future #42 plan-management entry points must be integrated after that PR is production safe. There is no new fake Money Out action here.
- App Store or TestFlight deployment requires separate release readiness.

## QA
- `testIssue48PhotoNormalizesWithoutChangingSavingRecords`: private local photo write/removal does not change target/current amounts or progress.
- `testIssue48RejectsUnreadableAndOversizedPhotoData`: invalid input fails.
- `testIssue48GoalDetailHeroAndEmptyMediaSafety`: launches native seeded dashboard, checks accessible Goals/Photos/Record actions, no zero-photo pagination, exports screenshot.

All QA references are first-party diagnostic-only; the DEBUG seed is independent of live Supabase.

## Remaining review criteria
- Compare native iPhone screenshot to Figma polished source, not research snapshots.
- Check long title, Dynamic Type, VoiceOver, low-resolution/wide images, permission denial and slow loading on an actual iPhone before shipping.
- The existing photo is stored in SwiftData on this device only; do not claim cloud photo backup.
