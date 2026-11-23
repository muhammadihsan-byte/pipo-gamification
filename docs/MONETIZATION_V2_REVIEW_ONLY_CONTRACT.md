# Pipo Monetization V2 — Entitlement Contract (REVIEW ONLY)

**Status 2026-11-23:** Product decisions documented; no StoreKit products, RLS migration, purchase verification, production SQL or paywall implementation in this document. Parent readiness: [Auth + Pay + Missing UX](NEXT_HANDOFF_AUTH_PAY_UX_READINESS_2026-11-23.md). Product gate [#87](https://github.com/muhammadihsan-byte/pipo-gamification/issues/87), server security gate [#28](https://github.com/muhammadihsan-byte/pipo-gamification/issues/28).

## Business truth

- Free: **2 concurrent personal goals + 1 concurrently occupied group creator slot**.
- Permanent Personal Slot: **$3.99 USD reference**; adds **one reusable personal goal capacity**, never destroyed by finishing/deleting goal.
- Permanent Group Slot: **$6.99 USD reference**; adds **one reusable concurrent group creator capacity**; **joining an existing group is free**.
- Personal Lifetime Pro: **$24.99 USD reference** one-time; personal goal count becomes unlimited. **Does not include group creator slots**.
- Group creator occupancy: Active/Paused **consume**; Completed/Archived/Deleted **release**. A permanently purchased slot is an entitlement; an individual group currently occupying it is *not* the purchased object.
- Global launch: actual price is `Product.displayPrice` from localized storefront. No hard-coded universal dollar amounts in paywalls. Product IDs, refund rules, creator-transfer and archive semantics require signed-off contract before implementation.

## Proposed typed boundaries (not shipping code)

```swift
// Conceptual DTO only; not a production model.
struct VerifiedEntitlementsV2 {
    let ownerID: UUID
    let personalLifetimePro: Bool    // Server-verified non-consumable candidate
    let permanentPersonalSlots: Int // Server-verified count, never client increment
    let permanentGroupSlots: Int    // Server-verified count, never client increment
    let revision: Int64             // Server-owned CAS/monotonic version
    let verifiedAt: Date
}
```

Proposed derived values:
```text
personal_capacity = unlimited if personalLifetimePro else 2 + permanentPersonalSlots
group_creator_capacity = 1 + permanentGroupSlots
occupied_personal = count(current owned personal goals consuming capacity under approved lifecycle rules)
occupied_group_creator = count(current owned group goals in [Active, Paused])
can_create_personal = Pro OR occupied_personal < personal_capacity
can_create_group = occupied_group_creator < group_creator_capacity
can_join_group = free (membership auth/authorization still required; never spends creator capacity)
```

**Gating:** A client-side visual display of availability is not proof of billing ownership. A future shared-group server must atomically reserve/release creator capacity with owner-scoped transaction locking or equivalent concurrency control to prevent simultaneous double allocation. Never grant slots by editing `UserProfile` or trusting a device count.

## Product catalog decision (draft mapping, NOT actual App Store product IDs)

| Logical SKU | Repeat buy? | Type / verification decision |
| --- | --- | --- |
| Personal +1 permanent capacity | **Yes** | Repeatable purchase requires deliberate Consumable IAP classification review + Apple-signed backend ledger and server-owned lifetime credits; consumables aren't Apple-restorable like non-consumables. |
| Group +1 permanent capacity | **Yes** | Same issue, **different SKU** and price from Personal. |
| Personal Lifetime Pro | **Once** | Non-consumable IAP candidate, verified/restorable across same Apple ID & bound Pipo account policy. |

Existing `com.pipo.goalslot` is a **$2 consumable dev test** in `StoreKit.storekit`; do not automatically repurpose that ID in an App Store catalog or orphan already purchased entitlements. No new product IDs are canonical until App Store Connect and support/restore policy are agreed.

Apple: [Types and repurchase rules](https://developer.apple.com/help/app-store-connect/reference/in-app-purchases-and-subscriptions/in-app-purchase-types), [Restoration](https://developer.apple.com/documentation/storekit/restoring-purchased-products), [App Review 3.1](https://developer.apple.com/app-store/review/guidelines/). Exact product classification and App Review acceptance are not guaranteed by the conceptual choice here.

## Proposed server-side proof-of-purchase flow

1. **Initiate:** Auth user and selected SKU/category are frozen with a request UUID and Apple `appAccountToken`; UI does not grant a slot.
2. **Purchase:** StoreKit produces signed purchase transaction or pending/cancel; show truthful states, preserve original transaction UUID. Do not replay with a new purchase automatically.
3. **Verify server-side:** Backend validates Apple-signed transaction and current product status, binds Apple transaction ID to exactly one approved Pipo user/product category, rejects account mismatches and duplication.
4. **Idempotent entitlement grant:** Under one atomic transaction, insert immutable purchase ledger entry, mint exactly one permanent credit or Lifetime Pro flag, increment server-owned entitlement revision; no direct client UPDATE grant.
5. **Acknowledge/recover:** Re-fetch authenticated server entitlements for current user, verify receipt and identity, update UI; keep pending intent if response ambiguous. Only finish Apple transaction after durable delivery contract is satisfied.
6. **Refund/revoke:** Consume Apple App Store Server Notification/verification status and apply documented, idempotent reversal/revocation policy; do **not** silently delete existing plans/savings/XP. Offer read-only or capacity-reached UX when appropriate.
7. **Reinstall/restore/account switch:** Re-fetch own server ledger after login; `AppStore.sync()` can refresh non-consumable purchases, but prior consumables must be restored from the **Pipo server ledger** with explicit account policy. Never use local counts as recovery authority.

### Backend proposals to review with #28

- `purchase_receipts` / `purchase_events`: unique Apple transaction ID + environment/storefront/product ID + verified signed proof identifier + bound owner + original transaction ID/refund/revocation state (sensitive data in private schema).
- `verified_entitlements_v2`: owner UUID, Pro flag, purchased personal/group counts, server-managed monotonically increasing version and timestamps, direct client write denied; RLS SELECT owner only.
- `creator_group_slot_allocations`: group UUID, owner UUID, occupied/released status, linked lifecycle transition; atomic uniqueness/owner-authorization. Do **not** retrofit live group membership that has not been built.
- Materialization and ledger semantics should be derived from immutable events; make grants idempotent and approvals/signing separate. Run signed A/B Auth/PostgREST isolation on disposable staging, not live users.

## UX surfaces needed before engineering handoff

1. **Capacity reached / choose path:** Distinguish Personal unlimited Pro vs permanent +1, Group creator slot separately; disclose “Pro does not include group slots” next to Lifetime purchase, not hidden in terms.
2. **Purchase checkout, Pending, Cancel, Verification failed:** Display localized Apple price, no fake purchase success, no added capacity before backend verifies.
3. **Owned plan & slots / Restore Purchases:** Show current permanently owned personal/group capacity, used versus free slots, personal Pro status, account and Apple ID recovery information.
4. **Group lifecycle / free joiner:** Confirm creator and membership semantics, no charge for invitee, reused group creator capacity on archived/completed/deleted, paused still consumes capacity.
5. **Offline and account mismatch:** Existing local plans and saved records remain accessible under correct owner; prohibit purchase or unauthorized sync while verified entitlement is stale; offer truthful retry.

## QA matrix (minimum)

| Scenario | Expected contract |
| --- | --- |
| New free user | Personal capacity **2**, group creator **1**, joiner **free** |
| Free user creates 2 personal plans | 3rd requires verified extra slot or Pro |
| User buys +1 Personal | Personal capacity 3; group unchanged |
| User buys +1 Group | Group creator capacity 2; personal unchanged |
| User activates Lifetime Pro | Personal unlimited; group capacity unchanged |
| Pro user with previously purchased personal slots | Keep purchase history; never destroy credit on conversion |
| Group Active → Paused | Still occupies group creator capacity |
| Group Paused → Completed/Archived/Deleted | Releases occupancy; lifetime credit remains |
| Group restored Active | New occupancy checked atomically, no double reservation |
| Guest joins another group | No creator slot deducted from guest |
| Duplicate Apple event / request replay | Exactly-once server grant |
| Refund/revoke | No silent loss of saved history; policy-driven restrict future capacity |
| App reinstall/second device | Server ledger recovers permanent group/personal credits |
| Apple ID vs Pipo owner mismatch | Fail closed, manual account recovery path |
| Offline/pending/failed Apple verification | No purchase success / no client-granted slot |
| Region and currency variation | StoreKit localized `displayPrice` and accessible disclosure |
| Concurrent creators/two devices | Atomic slot accounting and owner RLS |

**Blocking open decisions:** how to treat `archived` but still operational group, creator leaving/transfers, whether past unlimited personal upgrades merit credits, refund over-capacity behavior, legacy `com.pipo.goalslot` purchaser migration, deletion/retention policy for consumable ledger, and StoreKit product classification.

**Never infer deployment approval from this document or passed CI.**
