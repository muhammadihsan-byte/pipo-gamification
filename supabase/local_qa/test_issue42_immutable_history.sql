-- REVIEW-ONLY security QA, ephemeral PostgreSQL runner. NO customer rows.
-- Run AFTER the existing Issue 42 proposal. Every write is rolled back.
\set ON_ERROR_STOP on
BEGIN;
INSERT INTO auth.users(id) VALUES ('33333333-3333-4333-8333-333333333333'),
                                 ('44444444-4444-4444-8444-444444444444');
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','33333333-3333-4333-8333-333333333333',false);
DO $qa$
DECLARE blocked boolean; n integer;
BEGIN
    INSERT INTO public.saving_goals
       (id,title,category,target_amount,target_date,currency_code)
    VALUES ('c1111111-1111-4111-8111-111111111111','QA immutable USD',
       'gadget',100.00,now()+interval '30 days','USD');
    INSERT INTO public.saving_transactions
       (id,goal_id,amount,xp_earned,date)
    VALUES ('c2222222-2222-4222-8222-222222222222',
       'c1111111-1111-4111-8111-111111111111',0.01,5,'2026-11-22T01:00:00Z');
    -- Identical server UPSERT must not be blocked (stable transaction UUID).
    INSERT INTO public.saving_transactions
       (id,goal_id,amount,xp_earned,date)
    VALUES ('c2222222-2222-4222-8222-222222222222',
       'c1111111-1111-4111-8111-111111111111',0.01,5,'2026-11-22T01:00:00Z')
    ON CONFLICT(id) DO UPDATE SET
       amount=excluded.amount,xp_earned=excluded.xp_earned,date=excluded.date;

    blocked := false;
    BEGIN UPDATE public.saving_transactions SET amount=8
       WHERE id='c2222222-2222-4222-8222-222222222222';
    EXCEPTION WHEN check_violation THEN blocked:=true; END;
    IF NOT blocked THEN RAISE EXCEPTION 'FAIL: amount mutation allowed'; END IF;
    blocked := false;
    BEGIN UPDATE public.saving_transactions SET xp_earned=900
       WHERE id='c2222222-2222-4222-8222-222222222222';
    EXCEPTION WHEN check_violation THEN blocked:=true; END;
    IF NOT blocked THEN RAISE EXCEPTION 'FAIL: XP mutation allowed'; END IF;
    blocked := false;
    BEGIN
      INSERT INTO public.saving_transactions(id,goal_id,amount,xp_earned,date)
      VALUES ('c2222222-2222-4222-8222-222222222222',
         'c1111111-1111-4111-8111-111111111111',9.99,5,'2026-11-22T01:00:00Z')
      ON CONFLICT(id) DO UPDATE SET amount=excluded.amount;
    EXCEPTION WHEN check_violation THEN blocked:=true; END;
    IF NOT blocked THEN RAISE EXCEPTION 'FAIL: conflicting UUID replay allowed'; END IF;
    blocked := false;
    BEGIN DELETE FROM public.saving_transactions
       WHERE id='c2222222-2222-4222-8222-222222222222';
    EXCEPTION WHEN insufficient_privilege THEN blocked:=true; END;
    IF NOT blocked THEN RAISE EXCEPTION 'FAIL: DELETE granted to client'; END IF;
    SELECT count(*) INTO n FROM public.saving_transactions
      WHERE id='c2222222-2222-4222-8222-222222222222'
        AND amount=0.01 AND xp_earned=5;
    IF n<>1 THEN RAISE EXCEPTION 'FAIL: saved amount or XP changed'; END IF;
END $qa$;
RESET ROLE;
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','44444444-4444-4444-8444-444444444444',false);
DO $bob$
DECLARE n integer;
BEGIN
    SELECT count(*) INTO n FROM public.saving_transactions;
    IF n<>0 THEN RAISE EXCEPTION 'FAIL: foreign account can read history'; END IF;
END $bob$;
RESET ROLE;
ROLLBACK;
\echo 'PASS: Issue 42 immutable-history proposal, same-ID replay, owner/XP tampering rejected, owner isolation'
