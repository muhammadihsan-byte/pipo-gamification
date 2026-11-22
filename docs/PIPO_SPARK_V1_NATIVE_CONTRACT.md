# Pipo Spark V1 — Native Component Contract (#68)

Approved Figma: [20 standalone source variants](https://www.figma.com/design/tce3nRBcRwyObJMwQzA2rK/Gamification-Saving-SaaS?node-id=1498-3811) · [Five chip states](https://www.figma.com/design/tce3nRBcRwyObJMwQzA2rK/Gamification-Saving-SaaS?node-id=1500-9109) · [Semantic usage](https://www.figma.com/design/tce3nRBcRwyObJMwQzA2rK/Gamification-Saving-SaaS?node-id=1616-27350).

## Asset registry

Exported **directly from each approved Figma component at 3x PNG** to preserve the 16/20/24/40 optical tweaks, rather than reconstructing a similar-looking flame/star in SwiftUI or copying from a different system. All 20 variants live in `Pipo/Assets.xcassets`, with one uniform bundled asset naming convention.

| State | Source size, pt | Figma source node | Bundled image name |
|---|---:|---|---|
| NotStarted | 16 | `1498:3815` | `PipoSparkV1_NotStarted_16` |
| Active | 16 | `1498:3819` | `PipoSparkV1_Active_16` |
| Pending | 16 | `1498:3824` | `PipoSparkV1_Pending_16` |
| Ended | 16 | `1498:3828` | `PipoSparkV1_Ended_16` |
| Recovery | 16 | `1498:3833` | `PipoSparkV1_Recovery_16` |
| NotStarted | 20 | `1498:3837` | `PipoSparkV1_NotStarted_20` |
| Active | 20 | `1498:3841` | `PipoSparkV1_Active_20` |
| Pending | 20 | `1498:3846` | `PipoSparkV1_Pending_20` |
| Ended | 20 | `1498:3852` | `PipoSparkV1_Ended_20` |
| Recovery | 20 | `1498:3857` | `PipoSparkV1_Recovery_20` |
| NotStarted | 24 | `1498:3861` | `PipoSparkV1_NotStarted_24` |
| Active | 24 | `1498:3865` | `PipoSparkV1_Active_24` |
| Pending | 24 | `1498:3870` | `PipoSparkV1_Pending_24` |
| Ended | 24 | `1498:3876` | `PipoSparkV1_Ended_24` |
| Recovery | 24 | `1498:3881` | `PipoSparkV1_Recovery_24` |
| NotStarted | 40 | `1498:3886` | `PipoSparkV1_NotStarted_40` |
| Active | 40 | `1498:3891` | `PipoSparkV1_Active_40` |
| Pending | 40 | `1498:3897` | `PipoSparkV1_Pending_40` |
| Ended | 40 | `1498:3904` | `PipoSparkV1_Ended_40` |
| Recovery | 40 | `1498:3910` | `PipoSparkV1_Recovery_40` |

## Reusable component semantics

- `PipoSparkIcon(state:size:)`: actual source art in the exact requested optical size.
- `PipoSparkChip(presentation:)`: compact 42pt-reference SwiftUI chip with Dynamic Type growth, icon hidden from duplicate VoiceOver, and full spoken status on the chip.
- `PipoSparkPresentation.make(rhythm:proposedState:recordedSavings:consecutivePeriods:)` is **presentation-only**. Input must be derived from the owned goal's actual saved events and the rhythm engine. It must NOT create streaks or alter XP.
- `notStarted` = zero recorded savings OR no substantiated scheduled streak; `active` = scheduled current streak; `pending` = current period still open (not missed); `ended` = prior full scheduled period missed; `recovery` = resumed after such a missed period.
- Flexible cadence is ALWAYS rendered as `notStarted` artwork and **Saving at your pace** text, never pending/ended/recovery, even if a caller proposes an invalid status.
- No flame, older archived true-side Pipo, or achievement badge icons are reused. Pipo V4 remains reserved for milestone/celebration scenes.

## QA / release controls

- XCTest asserts all 20 actual bundled assets exist, maps each state uniquely and checks textual accessibility / flexible cadence semantics. Xcode previews show all states plus flexible without fabricated saving records in production.
- Screenshot optical parity on white and blush backgrounds at 1x/2x/3x and physical-device VoiceOver/Reduce Motion remain visual/device QA. A preview or simulator unit test does not prove physical-screen contrast.
- This component kit is intentionally NOT wired into Dashboard/Goal Detail until #69 validates a per-goal scheduled state against #14. No production SQL, TestFlight, or app release; merge requires final owner approval.

