# Saving consistency and approved Pipo achievements

Visual reference: https://www.figma.com/design/tce3nRBcRwyObJMwQzA2rK/Gamification-Saving-SaaS?node-id=321-4826

## Rules
- Daily = each local calendar day. Weekly = consecutive 7-calendar-day periods anchored to the goal start. Biweekly = 14-calendar-day periods. Monthly = calendar months, with planned contribution dates clamped to shorter month-ends.
- Flexible = record contributions without a streak or punitive reset.
- One scheduled period counts once, regardless of how many contributions it contains. An empty current period is pending rather than broken, but a fully missed period breaks the current chain.
- No invented pause / forgiveness policy until a user-controlled paused state exists. Saving again after a missed period starts a new chain and can earn Recovery.
- Only transactions owned by the active account and its goal may contribute. Widget, dashboard and saving milestone all use the same goal-specific calculation.
- Use Calendar date calculations to accommodate DST and month-end. The profile's old global streakDays is only the last recorded goal's value for backwards compatibility, never an authority to combine goals.

## Badge triggers from the 17-item Figma catalog
| Figma name | Stable ID | Real event | State |
| --- | --- | --- | --- |
| First Step | first-save | First account-owned saved contribution | Active |
| Plan in Action | plan-match | Contribution on exact planned date at or above planned amount | Active |
| Building Consistency | 3-planned | Three distinct planned contribution days on one goal | Active |
| Rhythm Established | 4-periods | Four consecutive planned periods on one goal | Active |
| Back on Track | recovery | Contribute after a fully missed scheduled period | Active |
| Goal Bonus | extra-save | An additional saving within an already contributed scheduled period | Active |
| Realistic Plan | adapt-go | Plan revision + later saving | Waiting for plan-edit workflow |
| Next Goal | next-goal | New goal after completing one | Waiting for goal lifecycle event |
| Quarter Way | quarter-way | Contribution crosses 25% | Active |
| Halfway There | halfway | Contribution crosses 50% | Active |
| Almost There | almost-there | Contribution crosses 75% | Active |
| Goal Achieved | goal-achieved | Contribution crosses 100% | Active |
| Saving Together | saving-together | Real group member event | Waiting for group backend |
| Supportive Friend | supportive-friend | Real member encouragement | Waiting for group backend |
| Pipo Grows | pipo-grows | Verified sustained period evolution | Deferred |
| Seasonal Saver | seasonal-saver | Three-month long-term saving behavior | Deferred |
| Multi-Goal Planner | multi-goal | Verified multi-goal consistency | Deferred |

All 17 approved illustrated badges are imported as native iOS assets. Earned, locked, and coming-later states are explicit. Badge IDs are stable per account; unlocks occur only from persisted saving events, idempotently in the same SwiftData save as the transaction, with rollback on failure. Pipo does not move, hold, or verify money, nor issue real invitations.
