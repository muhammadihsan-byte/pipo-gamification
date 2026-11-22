-- Pipo #80 — REVIEW ONLY / STAGING CUTOVER PROPOSAL
-- NOT APPLIED to live project jdboaaiiwkblxvejnhol.
--
-- Requires FIRST staging #29 immutable contribution/goal-delete ACL hardening,
-- then a signed app migration away from saving_goals.upsert(onConflict: "id").
-- Do NOT ship this script as an automatic deployment migration.
-- SECURITY REVIEW REQUIRED before disposable-staging execution.
BEGIN;

DO $preflight$
BEGIN
  IF to_regclass('public.saving_goals') IS NULL
      OR to_regclass('private.pipo_plan_revision_receipts') IS NOT NULL THEN
    RAISE EXCEPTION 'Pipo goal schema missing or CAS already installed; stop';
  END IF;
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='saving_goals'
      AND column_name='plan_revision'
  ) THEN
    RAISE EXCEPTION 'Plan revision column already exists; review drift';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_class
    WHERE oid='public.saving_goals'::regclass AND relrowsecurity
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname='public' AND tablename='saving_goals'
      AND policyname='pipo_goals_update_own' AND cmd='UPDATE'
  ) THEN
    RAISE EXCEPTION 'RLS or goal update policy does not match baseline';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE tgrelid='public.saving_goals'::regclass
      AND tgname='pipo_global_v1_immutable_currency' AND tgenabled <> 'D'
  ) THEN
    RAISE EXCEPTION 'Immutable goal currency trigger not installed';
  END IF;
  -- A hard dependency: old journal DELETE/UPDATE and goal DELETE must
  -- already have been removed via separately reviewed #29 staging ACL.
  IF has_table_privilege('authenticated','public.saving_goals','DELETE')
     OR has_table_privilege('authenticated','public.saving_transactions','UPDATE')
     OR has_table_privilege('authenticated','public.saving_transactions','DELETE') THEN
    RAISE EXCEPTION 'Apply and verify #29 append-only ACL in staging first';
  END IF;
  IF EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public'
      AND tablename='saving_goals' AND cmd='ALL'
  ) THEN
    RAISE EXCEPTION 'Unexpected broad goal policy; stop';
  END IF;
END
$preflight$;

-- Existing goals begin at revision 0. The only app-accessible revision
-- mutation after cutover is the guarded, authenticated CAS RPC below.
ALTER TABLE public.saving_goals
  ADD COLUMN plan_revision bigint NOT NULL DEFAULT 0
    CONSTRAINT saving_goals_plan_revision_nonnegative CHECK (plan_revision >= 0);

-- Even a manipulated client sending plan_revision on NEW goal INSERT cannot
-- set an authoritative revision. Goal creation remains owner-scoped via RLS.
CREATE FUNCTION public.pipo_plan_revision_insert_zero()
RETURNS trigger
LANGUAGE plpgsql SECURITY INVOKER SET search_path = ''
AS $initialize_revision$
BEGIN
  NEW.plan_revision := 0;
  RETURN NEW;
END
$initialize_revision$;
REVOKE ALL ON FUNCTION public.pipo_plan_revision_insert_zero()
  FROM PUBLIC, anon, authenticated;
CREATE TRIGGER pipo_plan_revision_initialize
BEFORE INSERT ON public.saving_goals
FOR EACH ROW EXECUTE FUNCTION public.pipo_plan_revision_insert_zero();

-- Durable, account-scoped receipts. No direct user access to this private
-- table, even to SELECT. The RPC returns a strict allowlisted snapshot.
CREATE TABLE private.pipo_plan_revision_receipts (
  owner_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  request_id uuid NOT NULL,
  goal_id uuid NOT NULL,
  expected_revision bigint NOT NULL CHECK (expected_revision >= 0),
  request_payload jsonb NOT NULL,
  accepted_revision bigint NOT NULL CHECK (accepted_revision > 0),
  result_snapshot jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (owner_id, request_id),
  CONSTRAINT pipo_plan_receipt_owned_goal
    FOREIGN KEY (goal_id, owner_id)
    REFERENCES public.saving_goals(id, user_id) ON DELETE CASCADE
);
ALTER TABLE private.pipo_plan_revision_receipts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE private.pipo_plan_revision_receipts
  FROM PUBLIC, anon, authenticated;
-- The private schema must remain outside PostgREST exposed schemas.

CREATE FUNCTION public.pipo_apply_plan_revision_v1(
  p_request_id uuid,
  p_goal_id uuid,
  p_expected_revision bigint,
  p_target_amount numeric,
  p_target_date timestamptz,
  p_rhythm text,
  p_preferred_saving_day smallint,
  p_planned_contribution_override numeric
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $apply_plan$
DECLARE
  v_owner uuid;
  v_goal public.saving_goals%ROWTYPE;
  v_request jsonb;
  v_receipt private.pipo_plan_revision_receipts%ROWTYPE;
  v_snapshot jsonb;
  v_zero_fraction boolean;
BEGIN
  v_owner := auth.uid();
  IF v_owner IS NULL OR p_request_id IS NULL OR p_goal_id IS NULL
     OR p_expected_revision IS NULL OR p_expected_revision < 0
     OR p_expected_revision >= 9223372036854775807 THEN
    RAISE EXCEPTION 'Missing auth or invalid goal/revision/request'
      USING ERRCODE='22023';
  END IF;
  IF p_target_amount IS NULL OR p_target_amount <= 0
     OR p_target_amount > 9999999999999.99
     OR p_target_amount <> trunc(p_target_amount, 2)
     OR p_target_date IS NULL
     OR p_rhythm IS NULL
     OR p_rhythm NOT IN ('daily','weekly','biWeekly','monthly','flexible')
     OR (p_preferred_saving_day IS NOT NULL AND
         (p_preferred_saving_day < 1 OR p_preferred_saving_day > 31))
     OR (p_rhythm IN ('daily','flexible') AND p_preferred_saving_day IS NOT NULL)
     OR (p_rhythm IN ('weekly','biWeekly')
         AND p_preferred_saving_day > 7)
     OR (p_planned_contribution_override IS NOT NULL AND
         (p_planned_contribution_override <= 0
          OR p_planned_contribution_override > 9999999999999.99
          OR p_planned_contribution_override <>
             trunc(p_planned_contribution_override, 2)))
     OR (p_rhythm='flexible' AND p_planned_contribution_override IS NOT NULL)
  THEN
    RAISE EXCEPTION 'Invalid future plan details' USING ERRCODE='22023';
  END IF;

  -- Lock the owned goal BEFORE looking for an existing receipt. Same-goal
  -- requests serialize; the second sees the receipt left by the first.
  SELECT * INTO v_goal FROM public.saving_goals
  WHERE id=p_goal_id AND user_id=v_owner FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Goal not found for authenticated account'
      USING ERRCODE='42501';
  END IF;
  IF p_target_date < v_goal.start_date THEN
    RAISE EXCEPTION 'Target date precedes original start date'
      USING ERRCODE='22023';
  END IF;

  -- Current app permits ISO currencies with only 0 or 2 digits.
  -- Back-end exactness must match that contract; do not convert currency.
  IF btrim(v_goal.currency_code) IN
      ('BHD','IQD','JOD','KWD','LYD','OMR','TND','CLF','UYW') THEN
    RAISE EXCEPTION 'Unsupported minor-unit precision for goal'
      USING ERRCODE='22023';
  END IF;
  v_zero_fraction := btrim(v_goal.currency_code) IN
      ('IDR','JPY','KRW','VND','CLP','PYG','ISK','BIF','DJF',
       'GNF','KMF','RWF','UGX','VUV','XAF','XOF','XPF');
  IF v_zero_fraction AND
      (p_target_amount <> trunc(p_target_amount, 0)
       OR (p_planned_contribution_override IS NOT NULL AND
           p_planned_contribution_override <>
              trunc(p_planned_contribution_override, 0))) THEN
    RAISE EXCEPTION 'Fractional amount disallowed for goal currency'
      USING ERRCODE='22023';
  END IF;

  v_request := jsonb_build_object(
    'target_amount', p_target_amount,
    'target_date_epoch_seconds', extract(epoch from p_target_date),
    'rhythm', p_rhythm,
    'preferred_saving_day', p_preferred_saving_day,
    'planned_contribution_override', p_planned_contribution_override
  );
  SELECT * INTO v_receipt FROM private.pipo_plan_revision_receipts
  WHERE owner_id=v_owner AND request_id=p_request_id;
  IF FOUND THEN
    IF v_receipt.goal_id = p_goal_id
       AND v_receipt.expected_revision=p_expected_revision
       AND v_receipt.request_payload=v_request THEN
      -- Exact replay returns the ORIGINAL receipt. It need not be the
      -- latest state after a separate subsequent successful plan edit.
      RETURN v_receipt.result_snapshot;
    END IF;
    RAISE EXCEPTION 'Request UUID reused with different plan payload'
      USING ERRCODE='23505';
  END IF;

  IF v_goal.plan_revision <> p_expected_revision THEN
    -- No write, no receipt. Client must fetch the latest owned goal and
    -- explicitly resolve conflicts. Never silently rebase or overwrite.
    RETURN jsonb_build_object(
      'status','conflict', 'goal_id',p_goal_id,
      'current_revision',v_goal.plan_revision
    );
  END IF;

  UPDATE public.saving_goals
  SET target_amount=p_target_amount,
      target_date=p_target_date,
      rhythm=p_rhythm,
      preferred_saving_day=p_preferred_saving_day,
      planned_contribution_override=p_planned_contribution_override,
      plan_revision=plan_revision + 1,
      updated_at=clock_timestamp()
  WHERE id=v_goal.id AND user_id=v_owner
  RETURNING * INTO v_goal;

  v_snapshot := jsonb_build_object(
    'status','applied', 'request_id',p_request_id,
    'goal_id',v_goal.id, 'currency_code',btrim(v_goal.currency_code),
    'accepted_revision',v_goal.plan_revision,
    'target_amount',v_goal.target_amount,
    'target_date',v_goal.target_date, 'rhythm',v_goal.rhythm,
    'preferred_saving_day',v_goal.preferred_saving_day,
    'planned_contribution_override',v_goal.planned_contribution_override
  );

  INSERT INTO private.pipo_plan_revision_receipts
    (owner_id,request_id,goal_id,expected_revision,request_payload,
     accepted_revision,result_snapshot)
  VALUES
    (v_owner,p_request_id,p_goal_id,p_expected_revision,v_request,
     v_goal.plan_revision,v_snapshot);
  -- A reused UUID on another goal fails the receipt primary key and the
  -- preceding UPDATE rolls back in the same SQL transaction.
  RETURN v_snapshot;
END
$apply_plan$;

-- Default EXECUTE on new functions is PUBLIC; make the RPC explicitly
-- authenticated-only. A SECURITY DEFINER function MUST check auth.uid().
REVOKE ALL ON FUNCTION public.pipo_apply_plan_revision_v1(
  uuid,uuid,bigint,numeric,timestamptz,text,smallint,numeric
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.pipo_apply_plan_revision_v1(
  uuid,uuid,bigint,numeric,timestamptz,text,smallint,numeric
) TO authenticated;

-- CRITICAL COMPATIBILITY: the #42 contribution trigger used SECURITY
-- INVOKER + SELECT FOR UPDATE on saving_goals. PostgreSQL requires UPDATE
-- privilege for FOR UPDATE, so removing goal UPDATE would otherwise break
-- legitimate saving INSERTs. Keep one server-owned goal row mutex shared by
-- deposits, money-out and plan CAS. Constrain this trigger definer to the
-- authenticated owner and the existing immutable row contents.
DO $guard_presence$
BEGIN
  IF to_regprocedure('public.guard_saving_contribution_immutable()') IS NULL
     OR NOT EXISTS (
       SELECT 1 FROM pg_trigger WHERE
         tgrelid='public.saving_transactions'::regclass
         AND tgname='pipo_immutable_contribution_guard' AND tgenabled <> 'D'
     ) THEN
    RAISE EXCEPTION 'Missing #42 immutable contribution guard; cannot safely cut over CAS';
  END IF;
END
$guard_presence$;

CREATE OR REPLACE FUNCTION public.guard_saving_contribution_immutable()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $contribution_guard$
DECLARE
  v_owner uuid;
BEGIN
  v_owner := auth.uid();
  IF v_owner IS NULL OR NEW.user_id IS DISTINCT FROM v_owner THEN
    RAISE EXCEPTION 'Authenticated contribution owner required'
      USING ERRCODE='42501';
  END IF;
  IF TG_OP = 'UPDATE' AND OLD.user_id IS DISTINCT FROM v_owner THEN
    RAISE EXCEPTION 'Historical contribution owner cannot change'
      USING ERRCODE='42501';
  END IF;

  -- A definer may take this lock after goal UPDATE is revoked from clients.
  -- Explicit owner binding is mandatory: never lock an unrelated goal.
  PERFORM 1 FROM public.saving_goals
  WHERE id=NEW.goal_id AND user_id=v_owner FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Owned goal unavailable for contribution'
      USING ERRCODE='42501';
  END IF;

  IF TG_OP = 'UPDATE' THEN
    IF row(OLD.id, OLD.goal_id, OLD.user_id, OLD.amount, OLD.xp_earned,
           OLD.date, OLD.created_at)
       IS DISTINCT FROM
       row(NEW.id, NEW.goal_id, NEW.user_id, NEW.amount, NEW.xp_earned,
           NEW.date, NEW.created_at) THEN
      RAISE EXCEPTION 'Saving contributions are immutable'
        USING ERRCODE='23514';
    END IF;
  END IF;
  RETURN NEW;
END
$contribution_guard$;
REVOKE ALL ON FUNCTION public.guard_saving_contribution_immutable()
  FROM PUBLIC, anon, authenticated;

-- ATOMIC CUTOVER: direct UPDATE must be removed in this same migration,
-- otherwise a modified iOS client could bypass revision checks entirely.
-- This breaks existing goal-first UPSERT. Do not apply until new clients use
-- INSERT-only for creation and the CAS RPC for all subsequent plan edits.
REVOKE UPDATE ON TABLE public.saving_goals FROM PUBLIC, anon, authenticated;
DROP POLICY pipo_goals_update_own ON public.saving_goals;

DO $postflight$
BEGIN
  IF has_table_privilege('authenticated','public.saving_goals','UPDATE')
     OR has_table_privilege('authenticated','public.saving_goals','DELETE')
     OR has_table_privilege('authenticated','private.pipo_plan_revision_receipts','SELECT')
     OR has_table_privilege('authenticated','private.pipo_plan_revision_receipts','INSERT')
     OR has_function_privilege('anon',
        'public.pipo_apply_plan_revision_v1(uuid,uuid,bigint,numeric,timestamptz,text,smallint,numeric)',
        'EXECUTE')
     OR NOT has_function_privilege('authenticated',
        'public.pipo_apply_plan_revision_v1(uuid,uuid,bigint,numeric,timestamptz,text,smallint,numeric)',
        'EXECUTE') THEN
    RAISE EXCEPTION 'Unsafe CAS privilege configuration; abort';
  END IF;
  IF EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public'
      AND tablename='saving_goals' AND cmd IN ('UPDATE','ALL')
  ) THEN
    RAISE EXCEPTION 'Direct goal-update RLS policy persists';
  END IF;
END
$postflight$;

COMMIT;

-- OPEN GATES (not addressed by executable SQL):
-- * #29 immutable journal ACL installed FIRST in staging.
-- * Signed client drops old goal UPSERT and uses INSERT / CAS / receipts.
-- * Budget breakdown remains local-only: this RPC does NOT synchronize
--   subitems and must not advertise end-to-end Manage Plan persistence.
-- * Profile, saving records, XP, achievements and local pending edits
--   have no automatic cross-device merge/restore here.
-- * Test two signed Auth accounts and actual concurrent sessions.
-- * Verify staging migrations/backups/rollback and obtain explicit approval.
