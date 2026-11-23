# Pipo V4 approved pose registry — source-only slice (#71)

Canonical approved Figma: [12 editable poses](https://www.figma.com/design/tce3nRBcRwyObJMwQzA2rK/Gamification-Saving-SaaS?node-id=1529-7055). Native source: `Pipo/Core/DesignSystem/PipoMascotView.swift`.

This change maps all 12 approved Figma pose IDs to typed Swift identifiers, separating **approved source** from **bundled runtime art**. It does **not** claim to export twelve assets. Existing bundled `PipoV4Neutral` is the safe fallback for poses that lack verified native exports; `PipoV4Joy` remains the existing celebration still and is not represented as a pixel-identical HandsUp export.

| Event context | Approved source pose | Figma node | Current runtime still |
| --- | --- | --- | --- |
| Resting / default | Idle | 1527:7055 | PipoV4Neutral |
| First eligible period noticed (after persisted event only) | SparkNoticed | 1527:7189 | PipoV4Neutral fallback |
| Earned milestone (after persisted award only) | HandsUp | 1527:7993 | PipoV4Joy existing approximation |
| Supportive recovery (no new badge) | GentleRecovery | 1527:8261 | PipoV4Neutral fallback |

Remaining approved source poses (unbundled): CuriousLean 1527:7323, ReachSpark 1527:7457, HugSpark 1527:7591, PresentSpark 1527:7725, MiniJump 1527:7859, ProudBest 1527:8127, CalmRest 1527:8395, HopefulLookUp 1527:8529. The registry includes all 12. Eight camera angles and twelve acting presets still require individual verified exports; **no claim of asset completeness**.

**Explicitly excluded:** archived true-side studies [1616:37846](https://www.figma.com/design/tce3nRBcRwyObJMwQzA2rK/Gamification-Saving-SaaS?node-id=1616-37846) and unapproved rear studies [1616:43698](https://www.figma.com/design/tce3nRBcRwyObJMwQzA2rK/Gamification-Saving-SaaS?node-id=1616-43698).

### Next integration gates

1. Export source components at appropriate resolutions with alpha, provenance and license verification. Compare optical bounds and anatomy on 320pt and 393pt devices.
2. Bind real persisted event/award contexts to reactions; do not infer success from screen navigation, goal creation, failed/offline-uncommitted saves or duplicate period logs.
3. Preserve Reduce Motion stills, VoiceOver copy, viewport pause, and safe-area placement. Current companion renderer already has Reduce Motion and viewport guards; this registry does not replace them.
4. Execute native build/XCTest and screenshot parity only when the owner re-enables Mac runner.

**Status:** source mapping candidate; no Xcode compilation, no native screenshot proof, no merge or production activation. Dependency #19/#20/#68; First Spark playback remains separate #72.
