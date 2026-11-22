# Pipo Issue #40 — First Save Activation V1 · Implementation and QA

Design source: [Figma 8-screen clickable flow](https://www.figma.com/design/tce3nRBcRwyObJMwQzA2rK/Gamification-Saving-SaaS?node-id=958-2239). Source issue: [#40](https://github.com/muhammadihsan-byte/pipo-gamification/issues/40).

## Product contract
- Keep the existing five-step goal wizard. After saving a goal, present **View my goal** or **I'll do it later**. Neither action adds money, XP, badges, bank transfers, or notifications.
- For the first zero-balance account-owned goal only, the main focus card and goal-detail footer offer **Record my first save**; when any account-owned saving exists or the first badge was previously awarded, use **Record a saving** instead. Other goals never claim another account first.
- The record sheet clearly states that money was saved elsewhere. The app records self-reported progress; it **does not transfer, verify or hold money**. No example amount is automatically filled.
- An invalid or failed local write leaves the sheet open, restores the pre-saving goal/profile values, shows inline error with accessible focus, and preserves the typed amount. A retry creates a new owned saving only after actual local persistence.
- **First Step** recognition derives only from the existing `AchievementEngine.grant` award after `modelContext.save()` succeeds. The one-shot Pipo V4 Joy view, "That counts!" bubble, +300 XP and actual earned first badge appear only for an eligible first saving. Subsequent saving milestones remain unchanged. Reduce Motion is already implemented inside `PipoMascotView`.
- Account switches clear pending sheets/milestones; target and currency do not change; the offline cloud sync remains a separate best-effort backup after local commit.

## QA
- Native XCTest main app build/unit/snapshot tests on PR exact head.
- UI simulator QA using the **isolated disk-backed synthetic user**: no-goal Home → actual five-step wizard → plan ready and later → zero-progress focus → manual sheet → deterministic failure while data and input remain → cancel → force-quit/relaunch with zero saving → successful retry → first badge and XP → real second launch without repeat celebration.
- The forced error is DEBUG-only and requires BOTH `-pipo-global-currency-qa` and `-pipo-first-save-force-persist-error`. It cannot run on a normal signed-in production session.
- Workflow `first-save-qa` records screenshots and MP4 into the seven-day GitHub Actions artifact, with explicit step success/failure.
- Real physical-device VoiceOver, larger Dynamic Type, keyboard focus, and Reduce Motion QA remain separate release validation gates. Test runner accessibility-tree assertions are not proof of real VoiceOver.

## Release control
No production SQL migration, real bank movement, deployment or TestFlight. Keep this PR unmerged until its exact-head CI and focused simulator evidence pass and the owner gives final merge approval.
