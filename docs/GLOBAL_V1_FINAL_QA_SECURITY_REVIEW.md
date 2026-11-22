# Pipo Global Experience V1 — Final QA and Security Review

Date: 2026-11-22 WIB. PR #58 remains a stacked **draft**. Read-only production audit; no production mutations.

## Verified current Supabase configuration
- Project pipo RLS is ON for saving_goals and saving_transactions. Owner checks exist on read/write policies.
- The enabled trigger pipo_global_v1_immutable_currency and migration 20261121215820_pipo_global_v1_immutable_goal_currency are **already in production**. Function is SECURITY INVOKER, uses explicit old/new currency comparison raising SQLSTATE 23514, and is not directly executable by PUBLIC/anon/authenticated. This was inspected via system catalogs only; no production Auth write test.
- **Unresolved security gap:** authenticated owners have UPDATE and DELETE privileges and RLS policies on saving_transactions. Without an immutable history guard, a client can change its own saved amount/XP or remove historical entries. Restricting ownership is not equivalent to making a ledger immutable.
- Security Advisor returned one unrelated INFO finding for early_access_signups (RLS enabled, no policy); assess separately if intended.

## CI evidence from head 7573325
- iOS: 121/121 unit/snapshot tests and 6/6 focused simulator tests PASS, including accessibility-tree large text and compact native DatePicker.
- Local synthetic Postgres + signed local Supabase Auth/PostgREST 2-account test PASSED; includes rejected offline request, exact-UUID retry, ambiguous-success replay, currency isolation.
- Live non-destructive Supabase Auth Smoke PASSED.
- Simulator QA is not physical VoiceOver QA. No signed iPhone airplane-mode session was executed.

## Security proposal compatibility extension
The local CI workflow now loads `supabase/proposals/issue_42_money_out_ledger_REVIEW_ONLY.sql` **only on disposable PostgreSQL and loopback-only local Supabase**. It tests identical UUID replay, conflicting duplicate rejection, owner amount/XP mutation rejection, client DELETE rejection, and account isolation. This is a proposal test, not a production schema migration or product enablement.

## Manual iPhone QA required before declaring final signoff
1. Real VoiceOver: focus order, spoken amounts/currency, DatePicker, 44-point touch targets, large text AX3/320pt, keyboard.
2. Offline: record personal saving; verify local XP/goal/journal; force quit and reopen offline; reconnect while app stays foregrounded without additional action; then background/foreground; verify one contribution per UUID, same amount, same XP and preserved currency; switch A to B and back.
3. Review simulator recordings/screenshots against approved Pipo Global V1 Figma, including create goal, relaunch, Manage Plan and unsaved review.

## Remaining release policy
- Approve and stage the separate immutable-contribution/DELETE restriction proposal after security review, real two-user auth tests and concurrency tests. Do not run the proposal against production until authorized.
- Coordinate multi-device stale goal UPSERT/versioning, crash recovery, and conflict policy. Current local-only saving retry is not proof of automatic network-path-triggered recovery.
- Keep Money Out cloud confirmation and Plan V2 final Save disabled. No merge/production deployment without owner's final approval after gates pass.
