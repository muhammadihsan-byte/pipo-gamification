# Pipo dev2 — Visual Polish V1 (review only)

Source of truth: approved [Manage Plan V2 / Option B Figma](https://www.figma.com/design/tce3nRBcRwyObJMwQzA2rK/Gamification-Saving-SaaS?node-id=1459-3369), [Global Experience V1 Option B Figma](https://www.figma.com/design/tce3nRBcRwyObJMwQzA2rK/Gamification-Saving-SaaS?node-id=1450-3369), and current SwiftUI on main at `5995e897`.

## Actual implementation audit

- Manage Plan already implements the approved overview → focused edit → change impact → unsaved review structure, but its overview progress and settings have weak surface separation.
- The `Current / Proposed` comparison was always a two-column `HStack`, risking collisions and narrow text on 320-point phones and larger Dynamic Type.
- Native goal-currency selection was a flat inline `HStack` with little differentiation for the selected currency or long localized currency names.
- The Manage Plan overview footer intentionally remains disabled until an edit is selected. Final Save stays disabled until secure revision persistence is implemented, authorized, and verified.

## Changes in this isolated polish branch

1. Strengthen the existing (single) manual-progress rail and move the saved-history reassurance into a distinct blush progress card.
2. Group goal-edit options into a bordered surface, preserving all existing actions, identifiers, and draft steps.
3. Use `ViewThatFits` for the unsaved change comparisons, preferring the existing horizontal pair only when values actually fit and stacking otherwise. Current vs proposed values use distinct neutral/blush surfaces.
4. Clarify selected vs unselected saving-rhythm controls without changing cadence logic.
5. Present goal currency as a full-width vertically readable code/name row, with a selected check and accessible selection trait. Strengthen the currency selector in Create Goal.
6. Reuse current Pipo colors and typography; no new theme, assets, or duplicated components.

## Safety & design gates

- No saving, sync, database, network, XP, badge, money-out, exchange-rate or currency conversion logic altered.
- Source currency remains immutable per created goal; changing draft currency resets unsaved amount/breakdown exactly as before.
- Existing Manage Plan V2 final Save remains intentionally unavailable. Never advertise this preview as a persistent change.
- A non-draft preview PR runs regular iOS build/XCTest and the focused `manage-plan-qa` simulator journey, exporting its screenshot attachments and MP4 in `ios-validation-<run-id>`.
- QA review: 320pt & 393pt widths, long currency names and nominal values, Dynamic Type, VoiceOver button traits, and no footer clipping.
- Required external release gates remain separate: real-device VoiceOver, offline/foreground retry and immutable journal + cross-device safety. No production SQL, deploy, TestFlight or merge is in scope.

**Status**: awaiting exact-head simulator evidence and user visual approval before merge.
