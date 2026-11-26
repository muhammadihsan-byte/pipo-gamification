# Pipo V4 motion polish

Base: `main` at `ff418e5`. Working branch: `feat/pipo-v4-motion-polish`.

The owner requested app-wide motion polish with Duolingo as a reference. This
pass uses anticipation, a readable gesture, secondary ear/flower motion, and a
soft settle. It retains Pipo V4 geometry, colors, original Alive Idle timeline,
neutral/joy assets, saving logic, account boundaries and reward eligibility.
No mascot assets or Figma files were regenerated.

Reference: Duolingo's [shape language](https://blog.duolingo.com/shape-language-duolingos-art-style/)
and [state-driven character animation](https://blog.duolingo.com/world-character-visemes/).
These inform timing and expressiveness; no Duolingo character assets are used.

## Placement and behavior

| Context | Motion |
| --- | --- |
| Welcome, Home | Existing V4 idle, articulated 960ms wave, light tap feedback, 1.1s tap debounce. Welcome's greeting is accessible to VoiceOver. |
| Sign in / Join Pipo | Small reassuring nod; another nod on new inline validation. No error celebration or shaking inputs. |
| Onboarding | Choice-driven wave, reassuring nod or encouragement through the shared rig; remove the competing whole-image wobble. Smooth progress and choice feedback. |
| Personal / Group Saving | Gentle step dissolve/lift; consistent raised-button press; finite Lottie illustrations suspend off-page/inactive. Pipo celebrates only on the existing persisted-success screens. |
| Home / Goals / Journey / Profile | Stable tab bar with subtle selection emphasis, content transitions, tactile cards and animated real progress updates. |
| Plan editing | Content transition inside the existing bounded sheet; draft owner and persistence behavior remain unchanged. |
| Milestones / First Spark | Brief joy anticipation and settle, reward-card entrance. First Spark retains the approved 780ms scaffold and gains cancellation on background/Reduce Motion changes. |
| Paywall | Reassuring V4 companion replaces the legacy Rive/image fallback route. No mascot distress used to encourage a purchase. |

The 780ms First Spark scene still uses its existing neutral illustration and
Spark choreography; this is **not** a newly exported, anatomical hug/reach
sequence. The current bundle does not contain those approved pose exports.

## Shared implementation

- `PipoMotion.swift`: 100ms press, 280ms soft release, 240ms page transition,
  restrained selection/arrival springs. Primary labels remain white.
- `PipoV4Motion.js`: offline bundled SMIL overlays on existing V4 anatomy.
  Reactions return to neutral without restarting idle. Fast events coalesce to
  one pending response; pause cancels active and queued work.
- `PipoMascotView.swift`: one V4 renderer, visible/foreground playback gate,
  neutral poster until two browser paint opportunities, fade into the rig,
  weak message-handler ownership, teardown and failure fallback.
- Reduce Motion uses approved stills, functional greeting feedback, no mascot
  movement, no button travel/scale, no tab bounce, and short page dissolves.
  Debug-only `-pipo-reduce-motion-qa` allows deterministic native QA and never
  overrides an enabled system setting to false.

## Verification

Completed locally:

- Five executable controller tests: paint readiness, finite neutral settlement,
  coalescing, background cancellation, unknown/missing anatomy safety.
- 27 existing focused checks: First Spark eligibility, account-safe UI
  integration, accessibility action targets and layout/primary-button guards.
- Tree-sitter grammar parsing of changed Swift, Xcode project parsing and
  source/resource membership, JavaScript syntax, whitespace.
- Chromium playback of all three rig reactions and pause/resume: no script
  errors; paused SVG clock remained still. A 12.36s MP4 was recorded separately
  for visual review. This proves browser rig playback, **not native iOS FPS**.
- Workflow lint: only the two existing owner-paused `if: false` jobs are flagged.

No local Xcode, iOS SDK or Swift compiler is available. Native compilation,
WebKit composition, UIKit haptics and actual-device smoothness are unverified.

## One focused native review

After approval, manually select `iOS Build and Test` → branch
`feat/pipo-v4-motion-polish` → `validation_mode: motion-qa`.
The new mode records one MP4 and retains xcresult/screenshots/diagnostics for:

1. Greeting, Home tabs and foreground recovery.
2. Reduce Motion greeting/navigation.
3. Core authentication screens.
4. Onboarding and choices.
5. Personal Saving end-to-end creation.
6. Group Saving end-to-end creation.

Review the recording for blank mascot frames, anatomy separation, reaction
overlap, field focus, footer collisions and abrupt settles. Check success and
First Spark under Reduce Motion on-device as well. The new mode is manual only;
draft updates cannot start a macOS build. Existing simulator selection,
concurrency cancellation and failure diagnostics remain intact.

This branch is a review candidate. It has not been merged or natively approved.
