-- Issue #29: SERVER-SIDE SAVING HISTORY GUARD · REVIEW ONLY
-- NOT APPLIED TO THE CONNECTED PRODUCTION SUPABASE PROJECT.
-- Target: a disposable staging database matching the verified 2026-11-22
-- public.saving_goals / public.saving_transactions policy and FK snapshot.
--
-- WARNING: this revokes direct client goal DELETE and journal UPDATE/DELETE.
-- The Auth-admin whole-account deletion flow deliberately still uses the
-- existing auth.users -> saving_goals / saving_transactions CASCADE.
-- Do not change those foreign keys as part of this patch.
--
-- Must run through a reviewed migration pipeline only after owner approval,
-- staging A/B auth QA, signed-app compatibility and backup/rollback validation.
BEGIN;

DO $preflight$
BEGIN
  IF to_regclass('public.saving_goals') IS NULL
      OR to_regclass('public.saving_transactions') IS NULL THEN
    RAISE EXCEPTION 'Missing Pipo saving schema; stop, no partial ACL changes';
  END IF;
  IF NOT (SELECT c.relrowsecurity FROM pg_class c
          WHERE c.oid = 'public.saving_goals'::regclass)
     OR NOT (SELECT c.relrowsecurity FROM pg_class c
             WHERE c.oid = 'public.saving_transactions'::regclass) THEN
    RAISE EXCEPTION 'RLS must be enabled on both saving tables';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname = 'public'
      AND tablename = 'saving_transactions'
      AND policyname = 'pipo_transactions_update_own' AND cmd = 'UPDATE'
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname = 'public'
      AND tablename = 'saving_transactions'
      AND policyname = 'pipo_transactions_delete_own' AND cmd = 'DELETE'
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname = 'public'
      AND tablename = 'saving_goals'
      AND policyname = 'pipo_goals_delete_own' AND cmd = 'DELETE'
  ) THEN
    RAISE EXCEPTION 'Unexpected RLS policy drift; stop and review snapshot';
  END IF;
  IF EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname = 'public'
      AND tablename IN ('saving_transactions','saving_goals')
      AND cmd = 'ALL'
  ) THEN
    RAISE EXCEPTION 'Unreviewed ALL policy could allow mutation';
  END IF;

  -- Whole-account Auth deletion must continue to cascade privately.
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'saving_goals_user_id_fkey'
      AND conrelid = 'public.saving_goals'::regclass AND confdeltype = 'c'
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'saving_transactions_user_id_fkey'
      AND conrelid = 'public.saving_transactions'::regclass AND confdeltype = 'c'
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'saving_transaction_owned_goal'
      AND conrelid = 'public.saving_transactions'::regclass AND confdeltype = 'c'
  ) THEN
    RAISE EXCEPTION 'Deletion FK drift; stop before affecting privacy erasure';
  END IF;
END
$preflight$;

-- Existing clients may SELECT/INSERT owned journal events, never rewrite
-- an existing amount/date/goal/XP or directly DELETE any journal entry.
-- PR #74 already switched transaction retries to ON CONFLICT DO NOTHING.
REVOKE UPDATE, DELETE ON TABLE public.saving_transactions
  FROM PUBLIC, anon, authenticated;
DROP POLICY pipo_transactions_update_own ON public.saving_transactions;
DROP POLICY pipo_transactions_delete_own ON public.saving_transactions;

-- Deleting an owned goal currently CASCADE-deletes its historical events.
-- Prevent direct client goal DELETE; do not alter Auth-admin erasure.
REVOKE DELETE ON TABLE public.saving_goals FROM PUBLIC, anon, authenticated;
DROP POLICY pipo_goals_delete_own ON public.saving_goals;

-- Owner/identity is not editable even during a legitimate plan edit.
-- A normal goal metadata upsert still has UPDATE+SELECT+INSERT grants and
-- retains the exact account-owned UPDATE/INSERT RLS policies.
CREATE OR REPLACE FUNCTION public.pipo_guard_goal_identity()
RETURNS trigger
LANGUAGE plpgsql SECURITY INVOKER SET search_path = ''
AS $goal_guard$
BEGIN
  IF OLD.id IS DISTINCT FROM NEW.id
     OR OLD.user_id IS DISTINCT FROM NEW.user_id
     OR OLD.created_at IS DISTINCT FROM NEW.created_at THEN
    RAISE EXCEPTION 'Goal identity and creation timestamp are immutable'
      USING errcode = '23514';
  END IF;
  RETURN NEW;
END
$goal_guard$;

REVOKE ALL ON FUNCTION public.pipo_guard_goal_identity()
  FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS pipo_guard_goal_identity_update ON public.saving_goals;
CREATE TRIGGER pipo_guard_goal_identity_update
BEFORE UPDATE OF id, user_id, created_at ON public.saving_goals
FOR EACH ROW EXECUTE FUNCTION public.pipo_guard_goal_identity();

DO $postflight$
BEGIN
  IF has_table_privilege('authenticated', 'public.saving_transactions', 'UPDATE')
    OR has_table_privilege('authenticated', 'public.saving_transactions', 'DELETE')
    OR has_table_privilege('authenticated', 'public.saving_goals', 'DELETE')
    OR has_table_privilege('anon', 'public.saving_transactions', 'UPDATE')
    OR has_table_privilege('anon', 'public.saving_transactions', 'DELETE')
    OR has_table_privilege('anon', 'public.saving_goals', 'DELETE') THEN
    RAISE EXCEPTION 'Journal mutation privilege persists; abort entire migration';
  END IF;
  IF NOT has_table_privilege('authenticated', 'public.saving_transactions', 'SELECT')
     OR NOT has_table_privilege('authenticated', 'public.saving_transactions', 'INSERT')
     OR NOT has_table_privilege('authenticated', 'public.saving_goals', 'SELECT')
     OR NOT has_table_privilege('authenticated', 'public.saving_goals', 'INSERT')
     OR NOT has_table_privilege('authenticated', 'public.saving_goals', 'UPDATE') THEN
    RAISE EXCEPTION 'Existing authenticated saving API would break; abort migration';
  END IF;
  IF EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname = 'public'
    AND ((tablename = 'saving_transactions' AND cmd IN ('UPDATE','DELETE','ALL'))
      OR (tablename = 'saving_goals' AND cmd IN ('DELETE','ALL')))
  ) THEN
    RAISE EXCEPTION 'Unsafe mutation RLS policy remains; abort migration';
  END IF;
END
$postflight$;

COMMIT;

-- This does not implement goal revisions/CAS, cross-device reconciliation,
-- safe journal correction, money-out, receipt validation or XP authority.
-- All remain release blockers tracked by #29 / #16 / #42.

