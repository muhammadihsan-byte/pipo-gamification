-- PIPO GLOBAL V1 — STAGING ONLY / SYNTHETIC & ROLLBACK ONLY
-- Run ONLY on an isolated Supabase branch AFTER applying the review-only
-- immutability trigger. Never execute against production, nor a customer DB.
-- This tests the actual installed trigger function without touching
-- public.saving_goals, auth.users, or public.saving_transactions.

BEGIN;

DO $probe$
DECLARE
    trigger_found boolean;
    rls_goals boolean;
    rls_transactions boolean;
BEGIN
    SELECT EXISTS (
        SELECT 1
        FROM pg_trigger t
        JOIN pg_class c ON c.oid = t.tgrelid
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'public'
          AND c.relname = 'saving_goals'
          AND t.tgname = 'pipo_global_v1_immutable_currency'
          AND t.tgenabled <> 'D'
    ) INTO trigger_found;
    IF NOT trigger_found THEN
        RAISE EXCEPTION 'FAIL: immutable-currency trigger is absent or disabled';
    END IF;

    SELECT c.relrowsecurity INTO rls_goals
      FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'public' AND c.relname = 'saving_goals';
    SELECT c.relrowsecurity INTO rls_transactions
      FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'public' AND c.relname = 'saving_transactions';
    IF NOT COALESCE(rls_goals, false) OR NOT COALESCE(rls_transactions, false) THEN
        RAISE EXCEPTION 'FAIL: expected goal/transaction RLS enabled';
    END IF;
END
$probe$;

CREATE TEMPORARY TABLE pipo_currency_qa_probe (
    id integer PRIMARY KEY,
    currency_code char(3) NOT NULL,
    target_amount numeric(15,2) NOT NULL
) ON COMMIT DROP;

CREATE TRIGGER pipo_currency_qa_probe_immutable
    BEFORE UPDATE OF currency_code ON pipo_currency_qa_probe
    FOR EACH ROW
    EXECUTE FUNCTION public.pipo_global_v1_prevent_currency_relabel();

INSERT INTO pipo_currency_qa_probe(id, currency_code, target_amount)
VALUES (1,'IDR',6000000), (2,'JPY',500000),
       (3,'USD',1500.50), (4,'EUR',3000.75);

-- App retries that keep the same currency must continue to work.
UPDATE pipo_currency_qa_probe SET currency_code='IDR' WHERE id=1;
UPDATE pipo_currency_qa_probe SET target_amount=1550.50 WHERE id=3;
UPDATE pipo_currency_qa_probe SET target_amount=1500.50 WHERE id=3;

DO $qa$
DECLARE
    blocked boolean := false;
    v integer;
BEGIN
    BEGIN
        UPDATE pipo_currency_qa_probe SET currency_code='USD' WHERE id=1;
    EXCEPTION WHEN check_violation THEN
        blocked := true;
    END;
    IF NOT blocked THEN
        RAISE EXCEPTION 'FAIL: stored IDR goal could be relabeled USD';
    END IF;

    blocked := false;
    BEGIN
        UPDATE pipo_currency_qa_probe SET currency_code='JPY' WHERE id=3;
    EXCEPTION WHEN check_violation THEN
        blocked := true;
    END;
    IF NOT blocked THEN
        RAISE EXCEPTION 'FAIL: stored USD goal could be relabeled JPY';
    END IF;

    SELECT count(*) INTO v FROM pipo_currency_qa_probe
     WHERE (id=1 AND currency_code='IDR' AND target_amount=6000000)
        OR (id=2 AND currency_code='JPY' AND target_amount=500000)
        OR (id=3 AND currency_code='USD' AND target_amount=1500.50)
        OR (id=4 AND currency_code='EUR' AND target_amount=3000.75);
    IF v <> 4 THEN
        RAISE EXCEPTION 'FAIL: synthetic currency or amount changed unexpectedly';
    END IF;
END
$qa$;

-- Nothing is retained, not even the temporary fixture.
ROLLBACK;
