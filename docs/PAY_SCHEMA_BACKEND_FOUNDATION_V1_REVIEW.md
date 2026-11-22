# Pipo Pay Schema Backend Foundation V1 — REVIEW ONLY

**Date:** 2026-11-23. **Issues:** [#28 server-authoritative billing](https://github.com/muhammadihsan-byte/pipo-gamification/issues/28), [#87 Monetization V2](https://github.com/muhammadihsan-byte/pipo-gamification/issues/87). **Status:** source-only schema proposal with disposable Postgres QA. No product registered, no verified Apple transaction received, no live SQL, no paid grant to a user, no signed checkout code, no Figma handoff requirement.

## Inputs and guardrails

- Current deployed Pipo baseline: `public.user_profiles` has server-owned `purchased_personal_slots` and `purchased_group_slots`, owner-SELECT only; **do not add client UPDATE/INSERT**. `public.saving_goals` still has no server-owned CAS revision; this project must not interfere with PR #83/#84/#85.
- Product rules: **Free 2 Personal + 1 Group creator**, $3.99 per permanent Personal extra capacity, $6.99 per permanent Group creator extra capacity, **Personal Lifetime Pro $24.99** unlimited **personal only**, group slots separately purchased; **joining groups is free**.
- Life-cycle consumption: creator's Active/Paused group consumes capacity, Completed/Archived/Deleted releases *occupancy*, **not the permanent credit**. Actual group membership and owner transfer are **not** implemented; this foundation does not authorize multi-device group create.
- Price localization remains **StoreKit product displayPrice**. No approved Apple product IDs or SKUs are created here. Current `com.pipo.goalslot` remains a **disabled old test consumable**; **StoreKitManager.purchasesEnabled stays false**.

## Data layout

```text
iPhone StoreKit2
  └── Apple-signed transaction / pending / revoke notification
        │ untrusted until backend cryptographic verification
        ▼
NEW Trusted server Apple JWS verifier + App Store Server API (NOT IMPLEMENTED)
        │ verifies signature chain / app bundle / environment / account token
        │ cross-account binding, product status and refund information
        ▼
service_role-only PostgREST RPC (source proposal only)
  public.pipo_internal_ingest_verified_apple_event_v1
        │ SECURITY INVOKER, GRANT service_role only
        ▼
  pipo_billing_private.apply_verified_apple_event_v1
        │
        ├── pipo_billing_private.apple_catalog [EMPTY; enabled=false default]
        ├── pipo_billing_private.apple_events [unique environment + Apple event ID]
        ├── pipo_billing_private.apple_transactions [unique environment + transaction ID]
        └── public.pipo_entitlements_v2 [server-owned, read-only to app]
                     │
                     ▼
 authenticated public.pipo_read_entitlements_v2() [owner from auth.uid()]
       └── free personal=2; free group creator=1;
           permanent personal/group counts; personal Lifetime Pro; revision
```

## Contract and security decisions

**Strict server boundary.** The private ingestion function is `SECURITY INVOKER`, in **unexposed private schema**, and requires `service_role`. A thin `public.pipo_internal_ingest_verified_apple_event_v1` wrapper exposes an Edge-function-compatible PostgREST RPC **only for service_role**; function EXECUTE is explicitly revoked from PUBLIC, anon and authenticated. This prevents accidentally exposing the billing schema to the Data API. Only a trusted Apple-verifying service may call it; neither iOS, an authenticated JWT, nor a publicly writable table is purchase evidence. `p_proof_sha256` is *a lookup/audit fingerprint*, **not** cryptographic proof. SQL intentionally cannot validate JWS certificate chains.

**No default sellable catalog.** The product mapping includes logical `personal_slot`, `group_slot`, `personal_lifetime_pro` and explicit Apple environment/product ID/bundle ID. All SKU rows must be inserted by an independently authorized release change after App Store Connect verification; proposed SQL seeds **zero rows**.

**Only immutable Apple identities can mint.** Each transaction is unique by (environment, Apple transaction ID) for all accounts, with owner bound to exact `appAccountToken`; an event ID must match its original full record. One purchased transaction yields one logical benefit; replay cannot increment a count. Refund/revoke is terminal for that transaction, including out-of-order notifications. Refund/revocation of an earlier **retired/disabled** catalog SKU is still allowed; new purchases from that SKU are denied. Lifetime Pro is a boolean from active, verified transactions, not a personal/group count.

**Atomic recomputation under per-owner row lock.** On each novel state transition, recompute counts from the transaction ledger and increase server revision; concurrent purchases for one Pipo account serialize on its entitlement row. An identical replay or terminal late purchase cannot increase benefits. Verified backend can request a current owner snapshot; the user app can only SELECT own snapshot via RLS or `pipo_read_entitlements_v2`.

**Account deletion.** The proposed account-linked ledger/events/snapshot cascade with `auth.users`, matching Pipo's privacy-oriented deletion flow. A **potential post-deletion Apple purchase reclaim or account transfer** remains unresolved: no global ownership tombstone survives account erasure. A retention/legal/recovery policy and Apple ID → Pipo account migration UX are **mandatory before deployment**.

**No existing-client bridge yet.** The new V2 snapshot is independent of the existing `public.user_profiles` purchased-slot fields. Existing iOS code continues its old view and free 1+1 limits. Do not expose V2 as a live entitlement authority or flip the paywall until a separately approved dual-read/migration approach handles old and new sources of truth. Never silently alter existing slot credits.

**Local tests do NOT verify Apple receipts.** The SQL harness invokes the service-only ingestion function with *synthetic placeholder hashes* solely to prove database privileges and state transitions; it must not be reported as end-to-end verified billing.

## Database acceptance / QA

Files:
- [Review-only schema](../supabase/proposals/issue28_pay_schema_v2_REVIEW_ONLY.sql)
- [Disposable PG17 test](../supabase/local_qa/test_issue28_pay_schema_v2.sql)
- [Static safety checks](../scripts/test_issue28_pay_schema_foundation.py)
- [CI](../.github/workflows/issue28-pay-schema-local-qa.yml)

Checks:
1. Production baseline preflight: `user_profiles` RLS, owner-SELECT only; fail closed on schema drift.
2. Empty catalog on installation; no SKU active from migration.
3. Client anon/authenticated role cannot read private Apple event ledger or write benefit counters/call service-only RPC.
4. A/B owner RLS and `pipo_read_entitlements_v2` derives correct **2+1 free** limits and separate purchased-category/lifetime status.
5. Same Apple event ID, different event ID for same Apple transaction, cross-account replay, forged appAccountToken, wrong bundle, disabled Production SKU.
6. Refund before purchase (terminal tombstone), refund after purchase, late purchase replay after refund, Lifetime Pro revocation, **retired SKU refund while new grant denied**, revision and count recomputation. Public wrapper rejects ordinary authenticated callers.
7. Auth-admin account deletion cascade; transactional test fixture fully rolled back.
8. Workflow uses **disposable postgres:17 GitHub Actions service** and source snapshot; no live Supabase connections or Apple billing.

## Next independent development gates

1. **Verifier architecture:** use validated Apple App Store Server API / JWS verification. Check actual Deno/Supabase Edge runtime library compatibility (cert-chain verifier support) before implementing; an incompatible library must **fail closed**, never switch to unchecked `atob` decoding. Protect server secrets, notification signature, environment, bundle/appAppleId, original transaction and current Apple status. [Apple validation](https://developer.apple.com/documentation/storekit/validating-receipts-with-the-app-store), [Supabase Edge Auth](https://supabase.com/docs/guides/functions/auth).
2. **App Store product model:** explicit final SKU IDs (separate repeatable consumables for permanent Personal/Group credits; non-consumable Lifetime Pro candidate), App Store Connect products, storefront prices, and notification V2 URL; **requires owner approval**. Repeatable consumables are restored from the Pipo account ledger, not automatically by Apple device restore.
3. **Refund and account-deletion policy:** decide whether refunded capacity over existing active goals blocks future creates without deleting savings; handle cross-account Apple ownership and legacy purchase imports; avoid retaining unnecessary personal data.
4. **Signed iOS auth & billing QA:** StoreKit sandbox, real signed Apple JWS, notification replay, authorized account A/B, duplicate purchases, two devices, offline/timeouts, refund/revocation, reinstall, group creator/guest roles, App Store Connect production product IDs.
5. **Integration:** implement client read-only `pipo_read_entitlements_v2` adapter, offline cached UX (no client grants), reconcile legacy `user_profiles` counts, then draft paywall behavior in Figma. **Do not enable checkout or client create enforcement before server verification and UX approvals.**
6. **Release:** distinct approvals required for production SQL/migration, edge function+secrets deployment, App Store product configuration, signed TestFlight and merge. Staging tests require **approved disposable** environment; a successful DB-only CI is not a production rollout gate.

## Explicitly excluded from this PR

No money movement, wallet balances, account auth flow redesign, Figma page updates, group invitations/membership, StoreKit product changes, production database writes, SwiftUI subscription manager changes, or merge.
