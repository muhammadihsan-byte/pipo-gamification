-- Pipo Issue #80 Budget CAS V2 — REVIEW ONLY, NEVER production.
-- Prerequisites in a DISPOSABLE staging DB:
-- #42 contribution guard -> #29 immutable ledger ACL -> #81 CAS V1.
-- This staged amendment replaces client access to CAS V1 with V2, atomically
-- versioning target/rhythm/date AND itemized budget in a single transaction.
-- It cannot fix signed OLD installed clients that still call goal UPSERT.
-- Legacy client compatibility/mandatory upgrade is a SEPARATE release gate.
BEGIN;

DO $preflight$
BEGIN
  IF to_regclass('public.saving_goals') IS NULL
     OR to_regclass('private.pipo_plan_revision_receipts') IS NULL
     OR to_regprocedure(
       'public.pipo_apply_plan_revision_v1(uuid,uuid,bigint,numeric,timestamptz,text,smallint,numeric)'
     ) IS NULL
     OR EXISTS (SELECT 1 FROM information_schema.columns
       WHERE table_schema='public' AND table_name='saving_goals'
         AND column_name='budget_snapshot_state')
     OR has_table_privilege('authenticated','public.saving_goals','UPDATE')
     OR has_table_privilege('authenticated','public.saving_transactions','UPDATE')
  THEN
    RAISE EXCEPTION 'Requires reviewed CAS V1 + append-only ACL; no partial budget upgrade';
  END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_class
       WHERE oid='public.saving_goals'::regclass AND relrowsecurity)
  THEN RAISE EXCEPTION 'Expected goal RLS is missing'; END IF;
END $preflight$;

-- Existing goals and newly inserted goals must NOT claim an empty cloud budget
-- is a faithful copy of their original SwiftData SubItem rows.
ALTER TABLE public.saving_goals
 ADD COLUMN budget_snapshot_state text NOT NULL DEFAULT 'needs_review'
 CHECK (budget_snapshot_state IN ('needs_review','synced'));

CREATE FUNCTION public.pipo_budget_initial_state_guard_v2()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path=''
AS $budget_guard$
BEGIN
 NEW.budget_snapshot_state := 'needs_review';
 RETURN NEW;
END $budget_guard$;
REVOKE ALL ON FUNCTION public.pipo_budget_initial_state_guard_v2()
 FROM PUBLIC, anon, authenticated;
CREATE TRIGGER pipo_budget_initial_state_guard_v2
 BEFORE INSERT ON public.saving_goals
 FOR EACH ROW EXECUTE FUNCTION public.pipo_budget_initial_state_guard_v2();

-- Never expose direct budget table writes or reads through the Data API.
CREATE TABLE private.pipo_plan_budget_items_v2 (
 owner_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
 goal_id uuid NOT NULL,
 item_id uuid NOT NULL,
 title text NOT NULL CHECK (length(btrim(title)) BETWEEN 1 AND 80),
 amount numeric(15,2) NOT NULL CHECK (amount > 0),
 is_completed boolean NOT NULL DEFAULT false,
 position integer NOT NULL CHECK (position BETWEEN 0 AND 63),
 created_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(owner_id,goal_id,item_id),
 UNIQUE(owner_id,goal_id,position),
 FOREIGN KEY(goal_id,owner_id) REFERENCES public.saving_goals(id,user_id)
   ON DELETE CASCADE
);
ALTER TABLE private.pipo_plan_budget_items_v2 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.pipo_plan_budget_items_v2
 FROM PUBLIC,anon,authenticated;

CREATE TABLE private.pipo_plan_budget_receipts_v2 (
 owner_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
 request_id uuid NOT NULL,
 goal_id uuid NOT NULL,
 expected_revision bigint NOT NULL CHECK(expected_revision>=0),
 request_payload jsonb NOT NULL,
 accepted_revision bigint NOT NULL CHECK(accepted_revision>0),
 result_snapshot jsonb NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(owner_id,request_id),
 FOREIGN KEY(goal_id,owner_id) REFERENCES public.saving_goals(id,user_id)
   ON DELETE CASCADE
);
ALTER TABLE private.pipo_plan_budget_receipts_v2 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.pipo_plan_budget_receipts_v2
 FROM PUBLIC,anon,authenticated;

-- A current, owner-scoped goal + budget readback, NOT a client-side cache.
-- The budget table stays inside the unexposed private schema.
CREATE FUNCTION public.pipo_read_plan_budget_v2(p_goal_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $read$
DECLARE
 v_owner uuid := auth.uid();
 v_goal public.saving_goals%ROWTYPE;
 v_items jsonb;
BEGIN
 IF v_owner IS NULL OR p_goal_id IS NULL THEN
   RAISE EXCEPTION 'Authenticated owned-goal read required' USING ERRCODE='42501';
 END IF;
 SELECT * INTO v_goal FROM public.saving_goals
   WHERE id=p_goal_id AND user_id=v_owner;
 IF NOT FOUND THEN
   RAISE EXCEPTION 'Owned goal unavailable' USING ERRCODE='42501';
 END IF;
 SELECT COALESCE(jsonb_agg(jsonb_build_object(
   'id',item_id,'title',title,'amount',amount,
   'is_completed',is_completed) ORDER BY position), '[]'::jsonb)
 INTO v_items FROM private.pipo_plan_budget_items_v2
 WHERE owner_id=v_owner AND goal_id=p_goal_id;
 RETURN jsonb_build_object(
   'status','snapshot','goal_id',v_goal.id,'currency_code',btrim(v_goal.currency_code),
   'plan_revision',v_goal.plan_revision,
   'budget_snapshot_state',v_goal.budget_snapshot_state,
   'target_amount',v_goal.target_amount,'target_date',v_goal.target_date,
   'rhythm',v_goal.rhythm,'preferred_saving_day',v_goal.preferred_saving_day,
   'planned_contribution_override',v_goal.planned_contribution_override,
   'items',v_items);
END $read$;
REVOKE ALL ON FUNCTION public.pipo_read_plan_budget_v2(uuid)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.pipo_read_plan_budget_v2(uuid)
 TO authenticated;

-- Always supply the *entire* ordered item array. [] deliberately clears
-- the budget only after explicit review, not by omitted/unknown payload.
CREATE FUNCTION public.pipo_apply_plan_budget_v2(
 p_request_id uuid,
 p_goal_id uuid,
 p_expected_revision bigint,
 p_target_amount numeric,
 p_target_date timestamptz,
 p_rhythm text,
 p_preferred_saving_day smallint,
 p_planned_contribution_override numeric,
 p_items jsonb,
 p_budget_import_confirmed boolean
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $apply$
DECLARE
 v_owner uuid := auth.uid();
 v_goal public.saving_goals%ROWTYPE;
 v_existing private.pipo_plan_budget_receipts_v2%ROWTYPE;
 v_input jsonb;
 v_item jsonb;
 v_id uuid;
 v_title text;
 v_amount numeric;
 v_completed boolean;
 v_ids uuid[] := ARRAY[]::uuid[];
 v_budget_total numeric := 0;
 v_count integer;
 v_pos integer := 0;
 v_whole_only boolean;
 v_result jsonb;
 v_snapshot jsonb;
BEGIN
 IF v_owner IS NULL OR p_request_id IS NULL OR p_goal_id IS NULL
    OR p_expected_revision IS NULL OR p_expected_revision < 0
    OR p_expected_revision >= 9223372036854775807
 THEN RAISE EXCEPTION 'Authenticated valid revision required' USING ERRCODE='22023'; END IF;
 IF p_target_amount IS NULL OR p_target_amount <= 0
    OR p_target_amount > 9999999999999.99
    OR p_target_amount <> trunc(p_target_amount,2)
    OR p_target_date IS NULL
    OR p_rhythm IS NULL
    OR p_rhythm NOT IN ('daily','weekly','biWeekly','monthly','flexible')
    OR (p_preferred_saving_day IS NOT NULL AND
        p_preferred_saving_day NOT BETWEEN 1 AND 31)
    OR (p_rhythm IN ('daily','flexible') AND p_preferred_saving_day IS NOT NULL)
    OR (p_rhythm IN ('weekly','biWeekly') AND p_preferred_saving_day > 7)
    OR (p_planned_contribution_override IS NOT NULL AND
        (p_planned_contribution_override <= 0
         OR p_planned_contribution_override > 9999999999999.99
         OR p_planned_contribution_override <> trunc(p_planned_contribution_override,2)))
    OR (p_rhythm='flexible' AND p_planned_contribution_override IS NOT NULL)
    OR p_items IS NULL OR jsonb_typeof(p_items) <> 'array'
    OR p_budget_import_confirmed IS NULL
 THEN RAISE EXCEPTION 'Invalid plan or missing explicit budget snapshot' USING ERRCODE='22023'; END IF;
 v_count := jsonb_array_length(p_items);
 IF v_count > 64 THEN
   RAISE EXCEPTION 'Too many budget items' USING ERRCODE='22023';
 END IF;

 -- One owner-scoped mutex shared with CAS V1 and contribution insert guard.
 SELECT * INTO v_goal FROM public.saving_goals
 WHERE id=p_goal_id AND user_id=v_owner FOR UPDATE;
 IF NOT FOUND THEN
   RAISE EXCEPTION 'Owned goal unavailable' USING ERRCODE='42501';
 END IF;
 IF p_target_date < v_goal.start_date THEN
   RAISE EXCEPTION 'Target date before start' USING ERRCODE='22023'; END IF;
 IF v_goal.budget_snapshot_state='needs_review'
    AND NOT p_budget_import_confirmed THEN
   RAISE EXCEPTION 'Budget not imported or explicitly reviewed'
     USING ERRCODE='22023';
 END IF;

 IF btrim(v_goal.currency_code) IN
   ('BHD','IQD','JOD','KWD','LYD','OMR','TND','CLF','UYW') THEN
   RAISE EXCEPTION 'Unsupported currency precision' USING ERRCODE='22023';
 END IF;
 v_whole_only := btrim(v_goal.currency_code) IN
   ('IDR','JPY','KRW','VND','CLP','PYG','ISK','BIF','DJF',
    'GNF','KMF','RWF','UGX','VUV','XAF','XOF','XPF');
 IF v_whole_only AND (p_target_amount <> trunc(p_target_amount,0)
    OR (p_planned_contribution_override IS NOT NULL AND
        p_planned_contribution_override <> trunc(p_planned_contribution_override,0))) THEN
   RAISE EXCEPTION 'Fractional amount for zero-decimal currency'
     USING ERRCODE='22023';
 END IF;

 FOR v_item IN SELECT value FROM jsonb_array_elements(p_items)
 LOOP
   IF jsonb_typeof(v_item) <> 'object'
      OR (SELECT count(*) FROM jsonb_object_keys(v_item) AS k(key)
           WHERE key NOT IN ('id','title','amount','is_completed')) > 0
      OR NOT (v_item ? 'id' AND v_item ? 'title'
              AND v_item ? 'amount' AND v_item ? 'is_completed')
      OR jsonb_typeof(v_item->'id') <> 'string'
      OR jsonb_typeof(v_item->'title') <> 'string'
      OR jsonb_typeof(v_item->'amount') <> 'number'
      OR jsonb_typeof(v_item->'is_completed') <> 'boolean'
   THEN RAISE EXCEPTION 'Invalid budget item object' USING ERRCODE='22023'; END IF;
   v_id := (v_item->>'id')::uuid;
   v_title := btrim(v_item->>'title');
   v_amount := (v_item->>'amount')::numeric;
   v_completed := (v_item->>'is_completed')::boolean;
   IF v_id = ANY(v_ids) OR length(v_title) NOT BETWEEN 1 AND 80
      OR v_amount <= 0 OR v_amount > 9999999999999.99
      OR v_amount <> trunc(v_amount,2)
      OR (v_whole_only AND v_amount <> trunc(v_amount,0))
   THEN RAISE EXCEPTION 'Invalid/duplicate budget item or precision'
     USING ERRCODE='22023'; END IF;
   v_ids := array_append(v_ids,v_id);
   v_budget_total := v_budget_total + v_amount;
 END LOOP;
 IF v_count > 0 AND v_budget_total <> p_target_amount THEN
   RAISE EXCEPTION 'Budget allocations must equal plan target'
     USING ERRCODE='22023';
 END IF;

 -- Exact byte/canonical JSON replay, before testing current revision.
 v_input := jsonb_build_object(
  'target_amount',p_target_amount,
  'target_date_epoch_seconds',extract(epoch from p_target_date),
  'rhythm',p_rhythm,'preferred_saving_day',p_preferred_saving_day,
  'planned_contribution_override',p_planned_contribution_override,
  'items',p_items,'budget_import_confirmed',p_budget_import_confirmed);
 SELECT * INTO v_existing FROM private.pipo_plan_budget_receipts_v2
 WHERE owner_id=v_owner AND request_id=p_request_id;
 IF FOUND THEN
   IF v_existing.goal_id=p_goal_id
      AND v_existing.expected_revision=p_expected_revision
      AND v_existing.request_payload=v_input THEN
     RETURN v_existing.result_snapshot;
   END IF;
   RAISE EXCEPTION 'Request UUID reused with changed plan/budget'
     USING ERRCODE='23505';
 END IF;
 IF v_goal.plan_revision <> p_expected_revision THEN
   RETURN jsonb_build_object(
    'status','conflict','goal_id',p_goal_id,
    'current_revision',v_goal.plan_revision);
 END IF;

 UPDATE public.saving_goals SET
  target_amount=p_target_amount,target_date=p_target_date,
  rhythm=p_rhythm,preferred_saving_day=p_preferred_saving_day,
  planned_contribution_override=p_planned_contribution_override,
  plan_revision=plan_revision+1,budget_snapshot_state='synced',
  updated_at=clock_timestamp()
 WHERE id=p_goal_id AND user_id=v_owner
 RETURNING * INTO v_goal;
 DELETE FROM private.pipo_plan_budget_items_v2
 WHERE owner_id=v_owner AND goal_id=p_goal_id;
 v_pos := 0;
 FOR v_item IN SELECT value FROM jsonb_array_elements(p_items)
 LOOP
   INSERT INTO private.pipo_plan_budget_items_v2
    (owner_id,goal_id,item_id,title,amount,is_completed,position)
   VALUES (v_owner,p_goal_id,(v_item->>'id')::uuid,
    btrim(v_item->>'title'),(v_item->>'amount')::numeric,
    (v_item->>'is_completed')::boolean,v_pos);
   v_pos:=v_pos+1;
 END LOOP;
 SELECT public.pipo_read_plan_budget_v2(p_goal_id) INTO v_snapshot;
 v_result := v_snapshot || jsonb_build_object(
   'status','applied','request_id',p_request_id,
   'accepted_revision',v_goal.plan_revision);
 INSERT INTO private.pipo_plan_budget_receipts_v2
 (owner_id,request_id,goal_id,expected_revision,request_payload,
  accepted_revision,result_snapshot)
 VALUES (v_owner,p_request_id,p_goal_id,p_expected_revision,v_input,
  v_goal.plan_revision,v_result);
 RETURN v_result;
END $apply$;
REVOKE ALL ON FUNCTION public.pipo_apply_plan_budget_v2(
 uuid,uuid,bigint,numeric,timestamptz,text,smallint,numeric,jsonb,boolean)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.pipo_apply_plan_budget_v2(
 uuid,uuid,bigint,numeric,timestamptz,text,smallint,numeric,jsonb,boolean)
 TO authenticated;

-- IMPORTANT: Leave ZERO authenticated callable plan mutation path without
-- atomic budget update after this reviewed staging upgrade.
REVOKE EXECUTE ON FUNCTION public.pipo_apply_plan_revision_v1(
 uuid,uuid,bigint,numeric,timestamptz,text,smallint,numeric)
 FROM PUBLIC,anon,authenticated;

DO $postflight$
BEGIN
 IF has_table_privilege('authenticated','public.saving_goals','UPDATE')
    OR has_table_privilege('authenticated','private.pipo_plan_budget_items_v2','SELECT')
    OR has_table_privilege('authenticated','private.pipo_plan_budget_items_v2','INSERT')
    OR has_table_privilege('authenticated','private.pipo_plan_budget_receipts_v2','SELECT')
    OR has_function_privilege('anon',
      'public.pipo_apply_plan_budget_v2(uuid,uuid,bigint,numeric,timestamptz,text,smallint,numeric,jsonb,boolean)','EXECUTE')
    OR NOT has_function_privilege('authenticated',
      'public.pipo_apply_plan_budget_v2(uuid,uuid,bigint,numeric,timestamptz,text,smallint,numeric,jsonb,boolean)','EXECUTE')
    OR has_function_privilege('authenticated',
      'public.pipo_apply_plan_revision_v1(uuid,uuid,bigint,numeric,timestamptz,text,smallint,numeric)','EXECUTE')
 THEN RAISE EXCEPTION 'Budget V2 grant or CAS V1 bypass remains'; END IF;
END $postflight$;
COMMIT;
-- REVIEW-ONLY. Not a migration. No old-client bridge, cloud-budget backfill,
-- Pipo iOS V2 client or production authorization is supplied by this SQL.
