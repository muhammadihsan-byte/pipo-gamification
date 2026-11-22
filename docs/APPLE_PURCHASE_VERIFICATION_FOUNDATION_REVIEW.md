# Pipo — Apple Purchase Verification Foundation (Node, REVIEW ONLY)

**Date:** 23 Nov 2026. **Scope:** developer-only backend security foundation, stacked on [draft Pay Schema PR #90](https://github.com/muhammadihsan-byte/pipo-gamification/pull/90); issues [#28](https://github.com/muhammadihsan-byte/pipo-gamification/issues/28), [#87](https://github.com/muhammadihsan-byte/pipo-gamification/issues/87). **NOT deployed. No production/Supabase writes. No sellable Apple SKU. No iOS checkout activation or Figma changes.**

## Runtime choice — fail closed rather than silently skip crypto

Apple's **official** \`@apple/app-store-server-library@3.1.0\` uses \`node:crypto.X509Certificate\` to validate leaf/intermediate chain against Apple's trusted root CAs. An October 2026 upstream report [supabase/edge-runtime#761](https://github.com/supabase/edge-runtime/issues/761) describes missing X509Certificate methods in **hosted Supabase Edge** with exactly this library, causing verification failures. Therefore **do not deploy the verifier to Supabase Edge** or replace certificate checks with \`atob\`/unenforced JWT decoding.

This implementation is a **standalone Node 22 service foundation**, with host started **only** on local loopback under explicit flag. A separately approved Node host (TLS gateway, upstream route, secure environment secret store, monitoring) is mandatory before production. The Supabase service-role-only PostgREST RPC from PR #90 remains the target ledger destination, **not a new public table or client grant**.

Official references:
- [Apple Node App Store Server Library](https://github.com/apple/app-store-server-library-node)
- [Apple App Store Server Notifications V2](https://developer.apple.com/documentation/appstoreservernotifications)
- [Apple official signed JWS verifier](https://apple.github.io/app-store-server-library-node/classes/SignedDataVerifier.html)
- [Supabase Edge upstream X509 runtime issue](https://github.com/supabase/edge-runtime/issues/761)

## Trust boundary

\`\`\`text
signed-in Pipo iOS client                     Apple Notifications V2
 POST /v1/verify-transaction                 POST /v1/notifications/{sandbox|production}
  JWT validated using Supabase /auth/v1/user       no bearer needed: OUTER JWS must verify
  client JWS VERIFIED with Apple roots             INNER signedTransactionInfo ALSO verifies
  appAccountToken == authenticated account         appAccountToken from INNER verified JWS
  Apple Server API getTransactionInfo              event UUID from OUTER verified JWS
  refresh returns CURRENT signed JWS               REFUND/REVOKE/ONE_TIME_CHARGE only
  latest JWS VERIFIED again                        unknown signed types acknowledged, not minted
  old/new transaction/account/product equal
          \                                           /
           \------ VERIFIED, owner-bound envelope --/
                                  |
                        PIPO_APPLE_LEDGER_WRITES_ENABLED
                          defaults FALSE, fails closed
                                  |
                     service-role-only PostgREST RPC
                      PR #90 pay v2 exact event ledger
                                  |
                      private Apple event + txn ledger
                                  |
                      owner RLS read-only entitlements
\`\`\`

**Never** authorize by \`client.user_id\`, client boolean \`verified\`, local counters, app user-metadata, transaction ID alone, arbitrary uploaded Apple root, or decoded-but-unsigned JWS body. Full JWS signature and X.509 chain checks use Apple library with **online certificate checks enabled**. Server checks exact app bundle, Apple app ID (production), environment, product allowlist, signed-date future bounds, appAccountToken UUID and transaction identities.

The signed user ID is retrieved via Supabase Auth. Signed Apple Notifications V2 need no Supabase user JWT; the signed appAccountToken authorizes the associated account. Missing appAccountToken must fail rather than guess an owner.

The source includes test dependency injection **only** for offline negative/authorization contract tests. It does NOT claim those synthetic signatures validate Apple's actual certificates. No root certificates, app IDs, API private keys, or real user data are committed.

## Environment configuration (no secrets committed)

| Variable | Purpose | Safe default |
| --- | --- | --- |
| \`PIPO_APPLE_HTTP_SERVER_ENABLED\` | Start loopback-only Node HTTP local host | disabled |
| \`PIPO_APPLE_LEDGER_WRITES_ENABLED\` | Allow requests to reach service-only RPC after full verification | **false** |
| \`PIPO_ALLOW_APPLE_SANDBOX\` | Accept Sandbox JWS at all | **false** |
| \`PIPO_APPLE_APPROVED_SKUS_JSON\` | Explicit allowlist, e.g. \`{"Sandbox":["qa.example.slot"],"Production":[]}\`; DB catalog must **independently** map and enable same SKU | **empty for both environments** |
| \`PIPO_APP_BUNDLE_ID\` | Exact Apple bundle ID | \`com.pipo.app\` |
| \`PIPO_APP_APPLE_ID\` | Required verified numeric appAppleId for Production | absent (reject) |
| \`PIPO_APPLE_ROOTS_DER_JSON\` | JSON array of **Apple PKI trusted root DER** certificates encoded base64; verify source and rotation | absent (reject) |
| \`PIPO_APPLE_API_ISSUER_ID\`, \`PIPO_APPLE_API_KEY_ID\`, \`PIPO_APPLE_API_PRIVATE_KEY_P8\` | Server-only App Store API credentials for fresh \`getTransactionInfo\` | absent (client reconciliation rejects) |
| \`SUPABASE_URL\`, \`SUPABASE_ANON_KEY\` | Auth \`/auth/v1/user\` for client proof | absent (reject) |
| \`SUPABASE_SERVICE_ROLE_KEY\` | Privileged RPC; **server-only**, never in iOS, logs or repo | absent (reject) |
| \`PIPO_APPLE_PORT\` | Local QA port >=1024 | 8788 |

Only owner-approved, **non-empty** catalog entries and Apple credentials can unlock actual processing, and the ledger gate still requires a separate owner-approved deployment. **Do not use the old \`com.pipo.goalslot\` test product** as a live offer. Real prices (free 2 Personal + 1 Group creator, $3.99/$6.99 slots, $24.99 personal Lifetime) are product decisions and must be localized by StoreKit in an approved UI later.

## API behavior for future signed staging only

- \`POST /v1/verify-transaction\` with Bearer Pipo JWT and JSON \`{"environment":"Sandbox","signedTransactionInfo":"<Apple JWS>"}\`. Mandatory auth lookup; server verifies the signed JWS, fetches Apple *current* transaction via App Store Server API, validates the **new** signed JWS, compares account/transaction/product/environment/bundle, then conditionally writes to RPC. Old valid but refunded transactions map to a refund event, never a new credit. Request fields besides JWS/environment are **never** the ownership authority.
- \`POST /v1/notifications/sandbox\` or \`/production\` with JSON \`{"signedPayload":"<Apple JWS>"}\`. Outer and inner JWS independently verified. Recognized \`ONE_TIME_CHARGE\` → purchased, \`REFUND\` → refunded, \`REVOKE\` → revoked. Other already-authenticated Apple notification types are currently acknowledged **without writing**. This MUST be revisited for refund reversal/consumption status and Apple notification history before shipping.
- When ledger writes are disabled or delivery cannot be confirmed, **HTTP 503** is returned, not a false purchase success. This is deliberately retryable for Apple notifications. Unknown signature errors return generic 422 without raw token exposure.

The service does **not** fetch or expose user-specific entitlements to the caller. The iOS client will later read signed-in owner RLS entitlement snapshots from PR #90, in a separate handoff.

## Current tests (scope matters)

\`services/apple-verifier/test/verification.test.mjs\` with \`node --test\` covers real Node X.509 API presence, missing trusted root rejection, auth-sourced user ID, cross-account rejection, malformed/invalid JWS error path, required Apple Server API current-status refresh, signed-data fields, disabled catalog/billing, service-only Supabase RPC, independent inner/outer notification verification, refund and no-bearer Apple notifications. These tests use **synthetic injected verifier results** to exercise authorization, *not* cryptographic positive fixtures.

\`.github/workflows/issue28-apple-verifier-node.yml\` exercises the pinned official library on Node 22 and runs the tests; lockfile must be committed and \`npm ci\` used before signoff. This is not a live Apple-sandbox proof.

## Gates still required before deploying or enabling checkout

1. Signed Apple sandbox transaction and Notifications V2 replay on the **actual hosting runtime**, with Apple-generated JWS and trusted PKI root certs; negative tampered signatures, real certificate expiration/OCSP and appAppleId mismatch.
2. Apple App Store Server API credentials, PKI roots, secrets, TLS, rate limiting, webhook URL, alerting, anti-abuse, privacy and reliable Notification History recovery.
3. Real Supabase **disposable staging** schema/catalog and service-role RPC integration; A/B users, cross-environment replay, account switch, appAccountToken and transactional idempotency. PR #90 schema still **review-only/unapplied**.
4. Product catalog / consumable versus nonconsumable decisions, retired SKU policy, account deletion Apple transaction reclaim and refund reversal/over-capacity behavior. Ensure permanently purchased slots are restorable from **Pipo server ledger** on reinstall.
5. Design-approved Auth/Paywall/Restore flows, signed StoreKit 2 iPhone QA, onboarding and account deletion impact analysis. No current iOS checkout enablement.
6. Distinct owner approvals for GitHub merge, Node hosting, Apple App Store Connect products/secrets, Supabase production SQL, and actual purchase activation. **No auto-merge.**

**Release status:** This is a secure integration *foundation*, not an operational purchase verifier in production.
