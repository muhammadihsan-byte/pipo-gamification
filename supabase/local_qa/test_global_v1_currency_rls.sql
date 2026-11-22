-- Pipo Global Experience V1 — local only, fully synthetic, rollback-only.
-- Execute AFTER bootstrap.sql and the exact review-only immutable trigger SQL.
-- Tests SQL RLS and foreign key semantics against a disposable PostgreSQL 17
-- instance. Auth JWTs are simulated; no network, Supabase production or users.
\set ON_ERROR_STOP on
BEGIN;

-- Both UUIDs are synthetic, deterministic, and never registered at Supabase.
INSERT INTO auth.users (id) VALUES
    ('11111111-1111-4111-8111-111111111111'),
    ('22222222-2222-4222-8222-222222222222');

DO $verify$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_trigger t
        WHERE t.tgrelid = 'public.saving_goals'::regclass
          AND t.tgname = 'pipo_global_v1_immutable_currency'
          AND t.tgenabled <> 'D'
    ) THEN
        RAISE EXCEPTION 'FAIL: currency guard trigger is not installed';
    END IF;
END $verify$;

-- Alice: create USD goal and one cent contribution, using authenticated RLS.
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '11111111-1111-4111-8111-111111111111', false);
DO $alice$
DECLARE
    count_own integer;
    blocked boolean := false;
    changed_rows integer;
BEGIN
    IF auth.uid() IS DISTINCT FROM '11111111-1111-4111-8111-111111111111'::uuid THEN
        RAISE EXCEPTION 'FAIL: Alice simulated auth subject is incorrect';
    END IF;

    INSERT INTO public.saving_goals
        (id, title, category, target_amount, target_date, currency_code)
    VALUES
        ('a1111111-1111-4111-8111-111111111111',
         'QA Alice USD laptop', 'gadget', 1500.50,
         now() + interval '90 days', 'USD');

    INSERT INTO public.saving_transactions
        (id, goal_id, amount, xp_earned)
    VALUES
        ('a3333333-3333-4333-8333-333333333333',
         'a1111111-1111-4111-8111-111111111111', 0.01, 5);

    SELECT count(*) INTO count_own
    FROM public.saving_goals
    WHERE id = 'a1111111-1111-4111-8111-111111111111'
      AND user_id = auth.uid()
      AND currency_code = 'USD' AND target_amount = 1500.50;
    IF count_own <> 1 THEN
        RAISE EXCEPTION 'FAIL: Alice USD 1500.50 lost precision or ownership';
    END IF;

    BEGIN
        UPDATE public.saving_goals SET currency_code = 'JPY'
        WHERE id = 'a1111111-1111-4111-8111-111111111111';
    EXCEPTION WHEN check_violation THEN
        blocked := true;
    END;
    IF NOT blocked THEN
        RAISE EXCEPTION 'FAIL: Alice could relabel persisted USD to JPY';
    END IF;

    -- Valid retries and non-currency edits must still be permitted.
    UPDATE public.saving_goals
    SET currency_code = 'USD', target_amount = 1550.50
    WHERE id = 'a1111111-1111-4111-8111-111111111111';
    GET DIAGNOSTICS changed_rows = ROW_COUNT;
    IF changed_rows <> 1 THEN
        RAISE EXCEPTION 'FAIL: same-currency retry was blocked';
    END IF;

    blocked := false;
    BEGIN
        UPDATE public.saving_goals
        SET user_id = '22222222-2222-4222-8222-222222222222'
        WHERE id = 'a1111111-1111-4111-8111-111111111111';
    EXCEPTION WHEN insufficient_privilege THEN
        blocked := true;
    END;
    IF NOT blocked THEN
        RAISE EXCEPTION 'FAIL: Alice could transfer goal ownership to Bob';
    END IF;

    SELECT count(*) INTO count_own FROM public.saving_transactions
    WHERE goal_id = 'a1111111-1111-4111-8111-111111111111'
      AND amount = 0.01 AND user_id = auth.uid();
    IF count_own <> 1 THEN
        RAISE EXCEPTION 'FAIL: Alice cent contribution was lost or mutated';
    END IF;
END $alice$;
\echo 'PASS: Alice USD 1500.50 + saving 0.01; immutable currency; safe same-currency retry; owner update denied'

-- Bob: independent JPY goal, plus negative cross-owner operations.
RESET ROLE;
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '22222222-2222-4222-8222-222222222222', false);
DO $bob$
DECLARE
    n integer;
    changed_rows integer;
    blocked boolean := false;
BEGIN
    INSERT INTO public.saving_goals
        (id, title, category, target_amount, target_date, currency_code)
    VALUES
        ('b2222222-2222-4222-8222-222222222222',
         'QA Bob JPY trip', 'trip', 500000,
         now() + interval '90 days', 'JPY');

    INSERT INTO public.saving_transactions
        (id, goal_id, amount, xp_earned)
    VALUES
        ('b4444444-4444-4444-8444-444444444444',
         'b2222222-2222-4222-8222-222222222222', 10, 2);

    SELECT count(*) INTO n FROM public.saving_goals;
    IF n <> 1 THEN RAISE EXCEPTION 'FAIL: Bob can see Alice goal or cannot see own'; END IF;
    SELECT count(*) INTO n FROM public.saving_transactions;
    IF n <> 1 THEN RAISE EXCEPTION 'FAIL: Bob can see Alice saving or cannot see own'; END IF;

    UPDATE public.saving_goals SET target_amount = 1
    WHERE id = 'a1111111-1111-4111-8111-111111111111';
    GET DIAGNOSTICS changed_rows = ROW_COUNT;
    IF changed_rows <> 0 THEN
        RAISE EXCEPTION 'FAIL: Bob updated Alice goal';
    END IF;

    DELETE FROM public.saving_transactions
    WHERE id = 'a3333333-3333-4333-8333-333333333333';
    GET DIAGNOSTICS changed_rows = ROW_COUNT;
    IF changed_rows <> 0 THEN
        RAISE EXCEPTION 'FAIL: Bob deleted Alice contribution';
    END IF;

    BEGIN
        INSERT INTO public.saving_goals
            (id, user_id, title, target_amount, target_date, currency_code)
        VALUES
            ('b5555555-5555-4555-8555-555555555555',
             '11111111-1111-4111-8111-111111111111',
             'Spoofed Alice', 100, now() + interval '30 days', 'EUR');
    EXCEPTION WHEN insufficient_privilege THEN
        blocked := true;
    END;
    IF NOT blocked THEN
        RAISE EXCEPTION 'FAIL: Bob inserted spoofed Alice-owned goal';
    END IF;

    blocked := false;
    BEGIN
        INSERT INTO public.saving_transactions
            (id, goal_id, user_id, amount)
        VALUES
            ('b6666666-6666-4666-8666-666666666666',
             'a1111111-1111-4111-8111-111111111111',
             '22222222-2222-4222-8222-222222222222', 4.50);
    EXCEPTION WHEN foreign_key_violation THEN
        blocked := true;
    END;
    IF NOT blocked THEN
        RAISE EXCEPTION 'FAIL: Bob linked a contribution to Alice goal';
    END IF;

    blocked := false;
    BEGIN
        UPDATE public.saving_goals SET currency_code = 'IDR'
        WHERE id = 'b2222222-2222-4222-8222-222222222222';
    EXCEPTION WHEN check_violation THEN
        blocked := true;
    END;
    IF NOT blocked THEN
        RAISE EXCEPTION 'FAIL: Bob relabeled JPY goal to IDR';
    END IF;
END $bob$;
\echo 'PASS: Bob JPY 500000; no Alice reads/updates/deletes; spoofed ownership rejected; composite FK; JPY lock'

-- Returning to Alice after switching accounts must not reveal Bob's data.
RESET ROLE;
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '11111111-1111-4111-8111-111111111111', false);
DO $reopen$
DECLARE n integer;
BEGIN
    SELECT count(*) INTO n FROM public.saving_goals
    WHERE id = 'a1111111-1111-4111-8111-111111111111'
      AND currency_code = 'USD' AND target_amount = 1550.50;
    IF n <> 1 THEN RAISE EXCEPTION 'FAIL: Alice goal changed after Bob attempts'; END IF;
    SELECT count(*) INTO n FROM public.saving_goals
    WHERE id = 'b2222222-2222-4222-8222-222222222222';
    IF n <> 0 THEN RAISE EXCEPTION 'FAIL: Alice can see Bob goal'; END IF;
    SELECT count(*) INTO n FROM public.saving_transactions
    WHERE id = 'b4444444-4444-4444-8444-444444444444';
    IF n <> 0 THEN RAISE EXCEPTION 'FAIL: Alice can see Bob saving'; END IF;
    SELECT count(*) INTO n FROM public.saving_transactions
    WHERE id = 'a3333333-3333-4333-8333-333333333333' AND amount = 0.01;
    IF n <> 1 THEN RAISE EXCEPTION 'FAIL: Alice saving was changed'; END IF;
END $reopen$;
\echo 'PASS: Alice reopening after account switch retains exact USD amount/history and Bob is isolated'

-- No fixture records remain after QA (and CI database is destroyed anyway).
RESET ROLE;
ROLLBACK;
\echo 'PASS: ALL GLOBAL EXPERIENCE V1 LOCAL POSTGRES CURRENCY + TWO-USER RLS CHECKS'
