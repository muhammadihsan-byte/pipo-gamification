-- Issue #80: staging-only SQL behavioural acceptance, NEVER production.
-- Requires separately reviewed #29 ACL + #80 CAS proposal applied on
-- disposable staging / local PostgreSQL with Supabase Auth fixtures.
-- Set PGOPTIONS="-c pipo.allow_synthetic_auth_qa=staging-only" ONLY on
-- that disposable database. This script intentionally creates temporary
-- synthetic Auth rows; every change is enclosed by BEGIN/ROLLBACK.
-- Actual simultaneous-session test is in docs/ISSUE_80_PLAN_CAS_STAGING_REVIEW.md.
\set ON_ERROR_STOP on
BEGIN;

DO $guard$
BEGIN
  IF current_setting('pipo.allow_synthetic_auth_qa', true)
      IS DISTINCT FROM 'staging-only' THEN
    RAISE EXCEPTION 'FAIL: explicit disposable staging guard missing';
  END IF;
  IF to_regclass('private.pipo_plan_revision_receipts') IS NULL
     OR NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema='public' AND table_name='saving_goals'
          AND column_name='plan_revision'
     ) THEN
    RAISE EXCEPTION 'FAIL: #80 staging proposal not installed';
  END IF;
  IF has_table_privilege('authenticated','public.saving_goals','UPDATE')
     OR has_table_privilege('authenticated','public.saving_goals','DELETE')
     OR has_table_privilege('authenticated','public.saving_transactions','UPDATE')
     OR has_table_privilege('authenticated','public.saving_transactions','DELETE') THEN
    RAISE EXCEPTION 'FAIL: direct write bypass/ledger mutation is still open';
  END IF;
  IF has_function_privilege('anon',
      'public.pipo_apply_plan_revision_v1(uuid,uuid,bigint,numeric,timestamptz,text,smallint,numeric)',
      'EXECUTE') THEN
    RAISE EXCEPTION 'FAIL: public/anon RPC execution privilege';
  END IF;
END
$guard$;

INSERT INTO auth.users(id) VALUES
  ('11111111-2222-4333-8444-555555555581'),
  ('11111111-2222-4333-8444-555555555582');

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub',
  '11111111-2222-4333-8444-555555555581', true);

-- A creates one wholly synthetic IDR goal and one historical contribution.
-- Attempt to spoof server-owned revision 999; trigger must force revision 0.
INSERT INTO public.saving_goals
  (id,title,category,target_amount,target_date,currency_code,plan_revision)
VALUES
  ('22222222-2222-4222-8222-222222222281',
   'Disposable goal A', 'trip', 300, now()+interval '35 days', 'IDR', 999);

INSERT INTO public.saving_transactions (id,goal_id,amount,xp_earned,date)
VALUES
  ('33333333-3333-4333-8333-333333333381',
   '22222222-2222-4222-8222-222222222281',50,300,now());

DO $a$
DECLARE
  r jsonb;
  v_count integer;
  denied boolean;
BEGIN
  IF (SELECT plan_revision FROM public.saving_goals
      WHERE id='22222222-2222-4222-8222-222222222281') <> 0 THEN
    RAISE EXCEPTION 'FAIL: client spoofed initial revision';
  END IF;

  SELECT public.pipo_apply_plan_revision_v1(
    '44444444-4444-4444-8444-444444444481',
    '22222222-2222-4222-8222-222222222281',
    0, 400, now()+interval '35 days', 'weekly', 2, 25)
  INTO r;
  IF r->>'status' <> 'applied'
     OR (r->>'accepted_revision')::bigint <> 1 THEN
    RAISE EXCEPTION 'FAIL: first CAS failed: %',r;
  END IF;

  -- An identical request UUID/payload returns ORIGINAL receipt, no +1.
  SELECT public.pipo_apply_plan_revision_v1(
    '44444444-4444-4444-8444-444444444481',
    '22222222-2222-4222-8222-222222222281',
    0, 400, now()+interval '35 days', 'weekly', 2, 25)
  INTO r;
  IF r->>'status' <> 'applied'
     OR (r->>'accepted_revision')::bigint <> 1 THEN
    RAISE EXCEPTION 'FAIL: byte-equivalent retry did not return receipt';
  END IF;

  SELECT public.pipo_apply_plan_revision_v1(
    '44444444-4444-4444-8444-444444444482',
    '22222222-2222-4222-8222-222222222281',
    0, 600, now()+interval '35 days', 'weekly', 2, 25)
  INTO r;
  IF r->>'status' <> 'conflict'
     OR (r->>'current_revision')::bigint <> 1 THEN
    RAISE EXCEPTION 'FAIL: stale revision was not rejected';
  END IF;

  denied:=false;
  BEGIN
    PERFORM public.pipo_apply_plan_revision_v1(
      '44444444-4444-4444-8444-444444444481',
      '22222222-2222-4222-8222-222222222281',
      0, 999, now()+interval '35 days', 'weekly', 2, 25);
  EXCEPTION WHEN unique_violation THEN denied:=true;
  END;
  IF NOT denied THEN
    RAISE EXCEPTION 'FAIL: UUID reused with changed payload accepted';
  END IF;

  denied:=false;
  BEGIN
    PERFORM public.pipo_apply_plan_revision_v1(
      '44444444-4444-4444-8444-444444444483',
      '22222222-2222-4222-8222-222222222281',
      1, 399.50, now()+interval '35 days', 'weekly', 2, 25);
  EXCEPTION WHEN invalid_parameter_value THEN denied:=true;
  END;
  IF NOT denied THEN
    RAISE EXCEPTION 'FAIL: fractional IDR accepted';
  END IF;

  denied:=false;
  BEGIN
    UPDATE public.saving_goals SET target_amount=999
    WHERE id='22222222-2222-4222-8222-222222222281';
  EXCEPTION WHEN insufficient_privilege THEN denied:=true;
  END;
  IF NOT denied THEN
    RAISE EXCEPTION 'FAIL: direct goal UPDATE bypass remains';
  END IF;

  SELECT count(*) INTO v_count FROM public.saving_transactions
  WHERE id='33333333-3333-4333-8333-333333333381'
    AND amount=50 AND xp_earned=300;
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'FAIL: original savings or XP were modified';
  END IF;
  IF (SELECT plan_revision FROM public.saving_goals
      WHERE id='22222222-2222-4222-8222-222222222281') <> 1 THEN
    RAISE EXCEPTION 'FAIL: failed calls mutated revision';
  END IF;
END
$a$;

SELECT set_config('request.jwt.claim.sub',
  '11111111-2222-4333-8444-555555555582', true);

DO $b$
DECLARE
  denied boolean:=false;
  v_count integer;
BEGIN
  SELECT count(*) INTO v_count FROM public.saving_goals
    WHERE id='22222222-2222-4222-8222-222222222281';
  IF v_count <> 0 THEN RAISE EXCEPTION 'FAIL: B can read A goal'; END IF;
  BEGIN
    PERFORM public.pipo_apply_plan_revision_v1(
      '44444444-4444-4444-8444-444444444484',
      '22222222-2222-4222-8222-222222222281',
      1, 900, now()+interval '35 days', 'monthly', 10, 100);
  EXCEPTION WHEN insufficient_privilege THEN denied:=true;
  END;
  IF NOT denied THEN
    RAISE EXCEPTION 'FAIL: account B could mutate A goal';
  END IF;
END
$b$;

RESET ROLE;
-- Private receipt and historical contribution are removed when the real
-- Auth admin deletes an account (both account deletions here roll back).
DELETE FROM auth.users WHERE id='11111111-2222-4333-8444-555555555581';
DO $privacy$
BEGIN
  IF EXISTS (SELECT 1 FROM private.pipo_plan_revision_receipts
             WHERE owner_id='11111111-2222-4333-8444-555555555581')
     OR EXISTS (SELECT 1 FROM public.saving_goals
                WHERE user_id='11111111-2222-4333-8444-555555555581') THEN
    RAISE EXCEPTION 'FAIL: Auth deletion did not erase plan receipts/goals';
  END IF;
END
$privacy$;

ROLLBACK;
\echo 'PASS (staging-only): revision 0 seed, CAS, retry, stale conflict, IDR precision, RLS, no XP mutation and Auth erasure'
