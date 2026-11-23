# Pipo — Next Handoff Readiness / Auth + Monetization + Missing UX

**Audit date:** 23 November 2026. **Status:** Read-only assessment and review-only handoff preparation; **not** a developer sign-off, implementation completion, signed TestFlight or production deployment.

**Canonical implementation:** `main` + explicitly reviewed feature branches. **Design monitor:** [Ihsan Space](https://www.figma.com/design/tce3nRBcRwyObJMwQzA2rK/Gamification-Saving-SaaS?node-id=1847-10188). **Approved engineering source:** [08 Developer Handoff](https://www.figma.com/design/tce3nRBcRwyObJMwQzA2rK/Gamification-Saving-SaaS?node-id=788-419), which does **not yet** contain the newly approved Auth/Paywall handoff.

## 1. Decisions to preserve

- **Pipo** is an iOS/SwiftUI app for **self-reported/manual savings**. It does not hold, move, automatically deposit or bank-verify funds.
- Release is global; app prices are displayed with **StoreKit-localized storefront pricing**, not hardcoded USD for all users.
- Existing Pipo V4 and approved card/Manage Plan/Global experience designs remain source unless explicitly superseded. UX approval ≠ engineering merge/deployment approval.
- Group creation is currently **device-local**, NOT remote membership, not a live invite URL and not a shared bank account.
- Keep PR [#83](https://github.com/muhammadihsan-byte/pipo-gamification/pull/83) CAS backend integration, [#84](https://github.com/muhammadihsan-byte/pipo-gamification/pull/84) budget recovery journal and [#85](https://github.com/muhammadihsan-byte/pipo-gamification/pull/85) legacy signed-client bridge **draft/unmerged**. Native Debug contract QA passed for #85; no live CAS/slot purchase cutover.

## 2. Authentication V1 status → [#86](https://github.com/muhammadihsan-byte/pipo-gamification/issues/86)

| Source | Current state | Engineering meaning |
| --- | --- | --- |
| [Welcome](https://www.figma.com/design/tce3nRBcRwyObJMwQzA2rK/Gamification-Saving-SaaS?node-id=1876-11113) | **UX approved** | Map to canonical design components/animations. No new auth semantics inferred. |
| [Login](https://www.figma.com/design/tce3nRBcRwyObJMwQzA2rK/Gamification-Saving-SaaS?node-id=1876-11385) | **UX approved** | Login UI may be mapped after 08 Handoff package. |
| [Sign Up](https://www.figma.com/design/tce3nRBcRwyObJMwQzA2rK/Gamification-Saving-SaaS?node-id=1876-11673) | **UX approved** | Signup UI may be mapped after 08 Handoff package. |
| [18 supporting states](https://www.figma.com/design/tce3nRBcRwyObJMwQzA2rK/Gamification-Saving-SaaS?node-id=1849-143) | **In Review** | Errors, loading, email verification, recovery, expired links, social interruption, offline states **cannot** be treated as approved handoff. |

Existing code: `Pipo/App/RootView.swift` renders `AuthView`; `Pipo/Core/Network/SupabaseService.swift` implements password auth/signup/reset session and account-delete function call; `Pipo/Core/Auth/AuthStateManager.swift` contains account-scoping. **Social sign-in remains disabled**, backend allowed redirect URLs and real device flow need verification. [#33](https://github.com/muhammadihsan-byte/pipo-gamification/issues/33) is the existing P0 release/security issue, not replaced here.

**Gates before auth coding:** canonical design handoff, explicit auth-provider choices, Figma state acceptance or deferral, account switches/deep-link handling and provider setup. **Gates before public launch:** signed real device, real email confirmation/reset, Apple/Google if advertised, deletion Edge Function, privacy and cross-account RLS tests. Do not conflate code presence with configured backend capability.

## 3. Monetization V2 truth → [#87](https://github.com/muhammadihsan-byte/pipo-gamification/issues/87)

| Product concept | Approved business rule / USD reference |
| --- | --- |
| Free | **2 personal goal slots + 1 group creator slot** |
| Permanent personal extra | **$3.99** each; +1 owned reusable capacity |
| Permanent group extra | **$6.99** each; +1 owned reusable creator capacity |
| Personal Lifetime Pro | **$24.99** once, unlimited personal goals **only**; group slots are separate |
| Joining someone else's group | **Free**; group creator capacity must not be charged to joiner |

Group creator capacity: **Active and Paused use capacity; Completed, Archived, Deleted free it**. Purchased capacity never expires. Open decisions: creators transferring/leaving, archive of active groups, legacy/grandfathered slot upgrades, refunds/revocation, upgrade discounts, and entitlements on account deletion.

**Code drift confirmed from `main`:** `SubscriptionManager.freePersonalSlots = 1`, `freeGroupSlots = 1`, no `personalLifetimePro`; `StoreKit.storekit` uses **one $2 Consumable** `com.pipo.goalslot` for personal and group; `PaywallView.swift` is an inactive placeholder; `StoreKitManager.purchasesEnabled = false`. Existing `public.user_profiles` stores server-owned purchased counts but there is **no production Apple verification ledger**.

[Backend verification gate #28](https://github.com/muhammadihsan-byte/pipo-gamification/issues/28) remains open. **Do not change billing code, production entitlements, App Store Connect, or enable checkout** from this product spec. Proposed contract detail is in [MONETIZATION_V2_REVIEW_ONLY_CONTRACT.md](MONETIZATION_V2_REVIEW_ONLY_CONTRACT.md).

**StoreKit decision:** A non-consumable IAP can be bought once; repeated slot purchases may require a consumable product with a **durable Pipo server ledger and app-owned restore**, and formal App Review/product-type consideration. Lifetime Pro is a non-consumable candidate. Confirm SKU type, restorable history and refund semantics before signing off [Apple IAP types](https://developer.apple.com/help/app-store-connect/reference/in-app-purchases-and-subscriptions/in-app-purchase-types).

## 4. Missing-page and UX status → [#88](https://github.com/muhammadihsan-byte/pipo-gamification/issues/88)

The [Figma section labelled “13 MISSING UI + 2 WIDGET / NOTIFICATION REVIEW”](https://www.figma.com/design/tce3nRBcRwyObJMwQzA2rK/Gamification-Saving-SaaS?node-id=1851-9330) has **0 child frames** in this audit. The label is a *historical counter*, **not a verified inventory of thirteen exact missing screens**. No named paywall/pricing/Restore/Lifetime frames were found in a read-only page/name scan. Do not invent missing nodes or hand off placeholder content.

| Product flow | GitHub behavior/source | Figma authority | Next action |
| --- | --- | --- | --- |
| Auth entry, Login, Sign Up | `RootView`, `AuthView`, `SupabaseService` | 3 approved core; 18 review states | Prepare canonical auth handoff; UX review still required |
| Post-login global onboarding | `OnboardingContainerView` + Global Experience V1 | Approved Global handoff exists | Regression only until explicitly revised |
| Personal goal create, review, first save | Implemented | Approved source | Keep; audit only UX deltas |
| Group goal create | Implemented device-local | Approved source | Do not imply real invitations |
| Group invitation / join | No real remote membership | [Design unverified](https://www.figma.com/design/tce3nRBcRwyObJMwQzA2rK/Gamification-Saving-SaaS?node-id=1849-5178) | Product/security approval required |
| Manage Plan V2 | partially implemented and gated by CAS #80 | UX approved; Save gated | Finish existing CAS/bridge transition independently |
| Money Out / corrections | contract + preview only | [Preview-only](https://www.figma.com/design/tce3nRBcRwyObJMwQzA2rK/Gamification-Saving-SaaS?node-id=1849-8388) | Requires UX and append-only backend ledger gate |
| Flexible Saving V2 | Existing rhythm exists; new experience differs | [In review](https://www.figma.com/design/tce3nRBcRwyObJMwQzA2rK/Gamification-Saving-SaaS?node-id=1849-11104) | Approval + behavior impact audit |
| Paywall, owned slots, Pro upgrade, Restore | Placeholder paywall, disabled checkout | **No approved handoff located** | Design / policy / StoreKit contract first |
| Widgets + notifications | Existing widget support, notifications exploration | V1/V2 visual review only | No release scope upgrade without approval |
| Account deletion / security settings | Some SwiftUI and Edge Function source exists | Supporting/auth states review | Real deployment/session A/B & policy QA first |

**Required approval vocabulary:** (1) concept drafted, (2) UX approved, (3) accepted in 08 Developer Handoff, (4) implemented on branch, (5) native/backend QA passed, (6) owner-approved merge, (7) signed release. These are never interchangeable.

## 5. Suggested execution order

1. **Complete this readiness audit** and track outstanding product decisions in #86–#88; no UI/source rewrites yet.
2. **Authentication V1 core-only Handoff** after canonical source+method approval; feature branch with asset fidelity/reduced-motion/accessibility and existing session behavior preserved.
3. **Monetization V2 state machine + trusted server ledger design**: first define SKU and entitlement contract, then create approved paywall/restore designs, then implement on isolated branch with StoreKit sandbox and trusted verification; do not activate checkout meanwhile.
4. **Missing-page design and UX review**, grouped in manageable handoff batches with concrete Figma node links; no monolithic implementation PR.
5. **Cross-feature QA**: pre/post upgrade signed auth users, account deletion/login restoration, goal slot accounting, CAS offline flows, StoreKit sandbox/restores, iPhone native + VoiceOver, global currencies and localizations.
6. **Explicit independent approvals** for PR merges, any signed client distribution, App Store products, and production SQL/schema cutover. Each must have rollback/monitoring decision; don't merge #83–#85 merely because their CI passed.

## 6. Current Supabase read-only audit

Project `jdboaaiiwkblxvejnhol` has RLS-enabled `saving_goals`, `saving_transactions`, `user_profiles` and marketing-only `early_access_signups`. App tables contain **0 rows as of this audit**, not a stand-in for real Auth A/B testing. The old `saving_goals` table has no server-owned `plan_revision`; the CAS PRs are proposals, not live migration. `user_profiles` paid slot balances are server owned but have no deployed trusted Apple verification ledger. **No SQL changes made.**

## 7. Sign-off summary

| Gate | Today |
| --- | --- |
| Auth Welcome/Login/Signup UX | **Approved in Figma only**, not new handoff |
| Auth supporting 18 states | **Review** |
| Monetization product rules | **Product direction approved**, code/design/server not implemented |
| Paywall/Restore/Lifetime design | **Missing approved handoff** |
| Missing UI exact count | **Unverified** (Figma label says 13, section currently empty) |
| PR #83/#84/#85 | **Draft / no merge / no production cutover** |
| Release/TestFlight | **Not authorized** |

**Owner's next approval is for the actual UX and paywall/auth handoff, not for payment activation or production deployment.**
