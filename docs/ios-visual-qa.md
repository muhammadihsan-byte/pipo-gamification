# Pipo iOS Simulator Visual QA

The **Visual QA** workflow records real interactions on the Pipo SwiftUI screens, not a slideshow of PNGs.

## Journeys

- `Pipo-Personal-Saving.mp4`: Dashboard → Personal Saving → goal and target → calendar interaction → rhythm → review → save → goal detail.
- `Pipo-Group-Saving.mp4`: Dashboard → Group Saving → goal/category → target → calendar → contribution rules → group setup → invite later → review → local save → dashboard.

These are **simulator UI tests**, not release or App Store tests. They use `-pipo-visual-qa` (compiled only in Debug) to present the real Dashboard while holding SwiftData in memory and skipping remote auth, StoreKit, and widget side effects. The videos contain synthetic test data.

## Trigger

After this workflow is present on the default branch: GitHub → Actions → **iOS Build and Test** → Run workflow → choose **Visual QA** and the desired branch. It is **not** run on ordinary commits or in the Build Only / Build + Test modes.

During initial review of `feat/pipo-ui-video-qa`, a one-time ready-for-review event runs the visual mode to validate the implementation. This is a single workflow job that records both journeys sequentially; it does not run the normal full suite again.

## Download

Open the successful workflow run → Artifacts → `ios-validation-<run-id>` → `validation/videos/`. The MP4s use H.264 for compatibility. Recordings and logs are kept for seven days; download any videos you want to retain.

The shell script verifies each MP4 has a valid `ftyp` header, finalized `moov` metadata, and meaningful size. Test errors fail the job; available partial recordings and logs are still uploaded for diagnosis.

## Scope

The recording tests touch the real UI, but they do not validate real OAuth, payments, photo permissions, invite delivery, cross-device synchronization, dynamic accessibility layouts, or TestFlight signing. They are visual QA evidence only. If a UI element changes, update the matching XCTest selector. Avoid rerunning full simulator validation after routine spacing or copy edits.
