-- Pipo #80 Budget CAS V2 tests; synthetic account data; ROLLBACK.
-- Requires prior staged #42 -> #29 -> #81 -> budget V2 on ephemeral PG17.
\set ON_ERROR_STOP on
BEGIN;
DO $guard$
BEGIN
 IF current_setting('pipo.allow_synthetic_auth_qa',true) <> 'staging-only'
    OR to_regclass('private.pipo_plan_budget_items_v2') IS NULL
    OR to_regprocedure('public.pipo_apply_plan_budget_v2(uuid,uuid,bigint,numeric,timestamptz,text,smallint,numeric,jsonb,boolean)') IS NULL
 THEN RAISE EXCEPTION 'TEST REFUSED: disposable budget v2 DB required'; END IF;
END $guard$;
INSERT INTO auth.users(id) VALUES
 ('99999999-1111-4111-8111-999999999981'),
 ('99999999-1111-4111-8111-999999999982');
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub',
 '99999999-1111-4111-8111-999999999981',true);
INSERT INTO public.saving_goals
 (id,title,category,target_amount,target_date,currency_code,budget_snapshot_state)
 VALUES ('99999999-2222-4222-8222-999999999981',
  'V2 synthetic saving','trip',300,'2030-01-01T00:00:00Z','IDR','synced');
INSERT INTO public.saving_transactions(id,goal_id,amount,xp_earned,date)
 VALUES ('99999999-3333-4333-8333-999999999981',
  '99999999-2222-4222-8222-999999999981',50,300,now());
DO $suite$
DECLARE
 r jsonb;
 budget jsonb:='[
  {"id":"99999999-4444-4444-8444-999999999981","title":"Ticket","amount":250,"is_completed":false},
  {"id":"99999999-4444-4444-8444-999999999982","title":"Hotel","amount":150,"is_completed":true}
 ]'::jsonb;
 denied boolean;
 n integer;
BEGIN
 IF (SELECT budget_snapshot_state FROM public.saving_goals
  WHERE id='99999999-2222-4222-8222-999999999981') <> 'needs_review' THEN
  RAISE EXCEPTION 'TEST FAIL: INSERT spoofed cloud budget synced state';
 END IF;
 IF has_function_privilege('authenticated',
  'public.pipo_apply_plan_revision_v1(uuid,uuid,bigint,numeric,timestamptz,text,smallint,numeric)','EXECUTE')
 THEN RAISE EXCEPTION 'TEST FAIL: legacy target-only CAS remains callable'; END IF;
 denied:=false;
 BEGIN
  PERFORM public.pipo_apply_plan_budget_v2(
   '99999999-5555-4555-8555-999999999984',
   '99999999-2222-4222-8222-999999999981',
   0,400,'2030-01-01T00:00:00Z','weekly',2::smallint,25,budget,false);
 EXCEPTION WHEN invalid_parameter_value THEN denied:=true; END;
 IF NOT denied THEN
  RAISE EXCEPTION 'TEST FAIL: budget import without review was permitted'; END IF;

 SELECT public.pipo_apply_plan_budget_v2(
  '99999999-5555-4555-8555-999999999981',
  '99999999-2222-4222-8222-999999999981',
  0,400,'2030-01-01T00:00:00Z','weekly',2::smallint,25,
  budget,true) INTO r;
 IF r->>'status' <> 'applied'
    OR (r->>'accepted_revision')::bigint <> 1
    OR r->>'budget_snapshot_state' <> 'synced'
    OR jsonb_array_length(r->'items') <> 2
    OR r->'items'->0->>'title' <> 'Ticket'
    OR r->'items'->1->>'is_completed' <> 'true'
 THEN RAISE EXCEPTION 'TEST FAIL: CAS budget/target not applied atomically %',r; END IF;

 SELECT public.pipo_apply_plan_budget_v2(
  '99999999-5555-4555-8555-999999999981',
  '99999999-2222-4222-8222-999999999981',
  0,400,'2030-01-01T00:00:00Z','weekly',2::smallint,25,
  budget,true) INTO r;
 IF r->>'status'<>'applied' OR (r->>'accepted_revision')::int<>1 THEN
   RAISE EXCEPTION 'TEST FAIL: idempotency did not return original receipt'; END IF;

 SELECT public.pipo_apply_plan_budget_v2(
  '99999999-5555-4555-8555-999999999982',
  '99999999-2222-4222-8222-999999999981',
  0,600,'2030-01-01T00:00:00Z','weekly',2::smallint,25,
  '[]'::jsonb,false) INTO r;
 IF r->>'status'<>'conflict' OR (r->>'current_revision')::int<>1 THEN
   RAISE EXCEPTION 'TEST FAIL: stale budget/goal request overwrote remote'; END IF;

 denied:=false;
 BEGIN
 PERFORM public.pipo_apply_plan_budget_v2(
  '99999999-5555-4555-8555-999999999981',
  '99999999-2222-4222-8222-999999999981',
  0,400,'2030-01-01T00:00:00Z','weekly',2::smallint,25,
  '[{"id":"99999999-4444-4444-8444-999999999981","title":"Ticket","amount":200,"is_completed":false},{"id":"99999999-4444-4444-8444-999999999982","title":"Hotel","amount":200,"is_completed":true}]'::jsonb,true);
 EXCEPTION WHEN unique_violation THEN denied:=true; END;
 IF NOT denied THEN
  RAISE EXCEPTION 'TEST FAIL: UUID reused with altered budget'; END IF;

 denied:=false;
 BEGIN
 PERFORM public.pipo_apply_plan_budget_v2(
  '99999999-5555-4555-8555-999999999983',
  '99999999-2222-4222-8222-999999999981',
  1,400,'2030-01-01T00:00:00Z','weekly',2::smallint,25,
  '[{"id":"99999999-4444-4444-8444-999999999981","title":"Ticket","amount":399,"is_completed":false}]'::jsonb,false);
 EXCEPTION WHEN invalid_parameter_value THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'TEST FAIL: mismatched total accepted'; END IF;

 denied:=false;
 BEGIN
 PERFORM public.pipo_apply_plan_budget_v2(
  '99999999-5555-4555-8555-999999999983',
  '99999999-2222-4222-8222-999999999981',
  1,400,'2030-01-01T00:00:00Z','weekly',2::smallint,25,
  '[{"id":"99999999-4444-4444-8444-999999999981","title":"Ticket","amount":200,"is_completed":false},{"id":"99999999-4444-4444-8444-999999999981","title":"Hotel","amount":200,"is_completed":false}]'::jsonb,false);
 EXCEPTION WHEN invalid_parameter_value THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'TEST FAIL: duplicate budget UUID accepted'; END IF;

 denied:=false;
 BEGIN
 PERFORM public.pipo_apply_plan_budget_v2(
  '99999999-5555-4555-8555-999999999983',
  '99999999-2222-4222-8222-999999999981',
  1,400.50,'2030-01-01T00:00:00Z','weekly',2::smallint,25,
  '[{"id":"99999999-4444-4444-8444-999999999981","title":"Ticket","amount":400.50,"is_completed":false}]'::jsonb,false);
 EXCEPTION WHEN invalid_parameter_value THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'TEST FAIL: fractional IDR accepted'; END IF;

 SELECT count(*) INTO n FROM public.saving_transactions WHERE
  id='99999999-3333-4333-8333-999999999981' AND amount=50 AND xp_earned=300;
 IF n<>1 THEN RAISE EXCEPTION 'TEST FAIL: saving history/XP was mutated'; END IF;
 IF (SELECT count(*) FROM private.pipo_plan_budget_items_v2
     WHERE goal_id='99999999-2222-4222-8222-999999999981')<>2 THEN
  RAISE EXCEPTION 'TEST FAIL: failed CAS altered budget rows'; END IF;
 IF (SELECT plan_revision FROM public.saving_goals
     WHERE id='99999999-2222-4222-8222-999999999981')<>1 THEN
  RAISE EXCEPTION 'TEST FAIL: failed CAS changed goal revision'; END IF;
END $suite$;

SELECT set_config('request.jwt.claim.sub',
 '99999999-1111-4111-8111-999999999982',true);
DO $other_user$
DECLARE r jsonb; denied boolean:=false;
BEGIN
 BEGIN
  SELECT public.pipo_read_plan_budget_v2(
   '99999999-2222-4222-8222-999999999981') INTO r;
 EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN
  RAISE EXCEPTION 'TEST FAIL: account B read account A private budget'; END IF;
 denied:=false;
 BEGIN
  PERFORM public.pipo_apply_plan_budget_v2(
   '99999999-5555-4555-8555-999999999985',
   '99999999-2222-4222-8222-999999999981',
   1,600,'2030-01-01T00:00:00Z','weekly',2::smallint,25,
   '[]'::jsonb,true);
 EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN
  RAISE EXCEPTION 'TEST FAIL: account B wrote account A budget'; END IF;
END $other_user$;
ROLLBACK;
\echo 'PASS: review-only budget CAS V2 atomic target/items, review gate, replay, conflict, RLS, currency, XP and rollback'
