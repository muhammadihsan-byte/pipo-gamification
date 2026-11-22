-- #29 staging-only acceptance checks. Run AFTER approved ACL migration
-- in disposable local/staging PostgreSQL. All fixture writes ROLLBACK.
-- psql -X -v ON_ERROR_STOP=1 -f supabase/local_qa/test_issue29_ledger_acl.sql
\set ON_ERROR_STOP on
BEGIN;

DO $contract$
BEGIN
  IF has_table_privilege('authenticated','public.saving_transactions','UPDATE')
     OR has_table_privilege('authenticated','public.saving_transactions','DELETE')
     OR has_table_privilege('authenticated','public.saving_goals','DELETE') THEN
    RAISE EXCEPTION 'FAIL: client history/goal DELETE or UPDATE still granted';
  END IF;
  IF NOT has_table_privilege('authenticated','public.saving_transactions','INSERT')
     OR NOT has_table_privilege('authenticated','public.saving_transactions','SELECT')
     OR NOT has_table_privilege('authenticated','public.saving_goals','UPDATE') THEN
    RAISE EXCEPTION 'FAIL: legitimate client insert or plan edit was removed';
  END IF;
END $contract$;

-- Disposable synthetic accounts, never real email identities or app data.
INSERT INTO auth.users(id) VALUES
 ('11111111-2222-4333-8444-555555555551'),
 ('11111111-2222-4333-8444-555555555552');

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub',
  '11111111-2222-4333-8444-555555555551',true);

INSERT INTO public.saving_goals
 (id,title,category,target_amount,target_date,currency_code)
VALUES ('22222222-2222-4222-8222-222222222221',
        'Synthetic account A', 'trip', 100.00,
        now() + interval '30 days', 'IDR');

INSERT INTO public.saving_transactions
 (id,goal_id,amount,xp_earned,date)
VALUES ('33333333-3333-4333-8333-333333333331',
        '22222222-2222-4222-8222-222222222221', 50, 300, now());

DO $owner_a$
DECLARE affected integer; denied boolean;
BEGIN
  -- Identical UUID retry succeeds as no-op without UPDATE rights.
  INSERT INTO public.saving_transactions
    (id,goal_id,amount,xp_earned,date)
  VALUES ('33333333-3333-4333-8333-333333333331',
          '22222222-2222-4222-8222-222222222221', 999, 999, now())
  ON CONFLICT(id) DO NOTHING;
  GET DIAGNOSTICS affected = ROW_COUNT;
  IF affected <> 0 THEN
    RAISE EXCEPTION 'FAIL: replayed transaction was inserted';
  END IF;

  SELECT count(*) INTO affected FROM public.saving_transactions
  WHERE id='33333333-3333-4333-8333-333333333331'
    AND amount=50 AND xp_earned=300;
  IF affected <> 1 THEN RAISE EXCEPTION 'FAIL: immutable event overwritten'; END IF;

  denied := false;
  BEGIN
    UPDATE public.saving_transactions SET amount=500 WHERE
      id='33333333-3333-4333-8333-333333333331';
  EXCEPTION WHEN insufficient_privilege THEN denied := true;
  END;
  IF NOT denied THEN RAISE EXCEPTION 'FAIL: journal UPDATE permitted'; END IF;

  denied := false;
  BEGIN
    DELETE FROM public.saving_transactions WHERE
      id='33333333-3333-4333-8333-333333333331';
  EXCEPTION WHEN insufficient_privilege THEN denied := true;
  END;
  IF NOT denied THEN RAISE EXCEPTION 'FAIL: journal DELETE permitted'; END IF;

  denied := false;
  BEGIN
    DELETE FROM public.saving_goals WHERE
      id='22222222-2222-4222-8222-222222222221';
  EXCEPTION WHEN insufficient_privilege THEN denied := true;
  END;
  IF NOT denied THEN RAISE EXCEPTION 'FAIL: goal CASCADE DELETE permitted'; END IF;

  -- Still allow legitimate metadata changes; owner/goal ID unchanged.
  UPDATE public.saving_goals SET title='Synthetic A revised'
    WHERE id='22222222-2222-4222-8222-222222222221';
  SELECT count(*) INTO affected FROM public.saving_goals
  WHERE id='22222222-2222-4222-8222-222222222221'
    AND title='Synthetic A revised';
  IF affected <> 1 THEN RAISE EXCEPTION 'FAIL: safe goal edit was blocked'; END IF;
END
$owner_a$;

-- Different signed-in user cannot read or forge A's owned transactions.
SELECT set_config('request.jwt.claim.sub',
  '11111111-2222-4333-8444-555555555552',true);
DO $owner_b$
DECLARE visible_count integer; denied boolean := false;
BEGIN
  SELECT count(*) INTO visible_count FROM public.saving_transactions;
  IF visible_count <> 0 THEN RAISE EXCEPTION 'FAIL: B sees A journal'; END IF;
  BEGIN
    INSERT INTO public.saving_transactions
      (id,goal_id,amount,xp_earned,date)
    VALUES ('33333333-3333-4333-8333-333333333332',
            '22222222-2222-4222-8222-222222222221',
            20, 300, now());
  EXCEPTION WHEN foreign_key_violation OR insufficient_privilege
                   OR check_violation OR with_check_option_violation
    THEN denied := true;
  END;
  IF NOT denied THEN RAISE EXCEPTION 'FAIL: cross-account fake journal accepted'; END IF;
END $owner_b$;

RESET ROLE;
-- Admin Auth deletion should preserve legitimate all-account erasure despite
-- revoked *client* DELETE privileges; FK ON DELETE CASCADE stays intact.
DELETE FROM auth.users WHERE id='11111111-2222-4333-8444-555555555551';
DO $erasure$
BEGIN
 IF EXISTS (
    SELECT 1 FROM public.saving_goals
    WHERE user_id='11111111-2222-4333-8444-555555555551'
 ) OR EXISTS (
    SELECT 1 FROM public.saving_transactions
    WHERE user_id='11111111-2222-4333-8444-555555555551'
 ) THEN RAISE EXCEPTION 'FAIL: whole-account Auth erasure did not cascade'; END IF;
END $erasure$;
ROLLBACK;
\echo 'PASS: Issue #29 staging ACL, idempotent insert, owner A/B isolation, goal deletion guard, Auth erasure'
