-- PIPO GLOBAL EXPERIENCE V1 — REVIEW ONLY, NOT A PRODUCTION MIGRATION
-- Do not execute against the production project without explicit approval.
-- Intended first for a disposable Supabase development branch.
--
-- Goal-level currency is immutable AFTER INSERT. Users can freely select
-- currency inside the unsigned Create Goal draft, but no client may relabel
-- a stored IDR/JPY/USD/EUR goal (even if transaction history is currently
-- empty). This is intentionally stronger than "lock after first saving":
-- it removes time-of-check/time-of-use races with concurrent contributions
-- and protects retries from older app clients omitting currency_code.
--
-- Supabase public.saving_goals.currency_code exists as char(3) default IDR.
-- This does not change columns, backfill data, XP, ledger or RLS policies.
-- Any eventual governed currency conversion needs a separate server-side
-- procedure; it MUST NOT bypass this trigger accidentally.

BEGIN;

CREATE OR REPLACE FUNCTION public.pipo_global_v1_prevent_currency_relabel()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog
AS $guard$
BEGIN
    IF NEW.currency_code IS DISTINCT FROM OLD.currency_code THEN
        RAISE EXCEPTION
            USING
                ERRCODE = '23514',
                MESSAGE = 'The currency of a saved Pipo goal cannot be changed.',
                HINT = 'Create a new goal, or use an explicitly approved migration.';
    END IF;
    RETURN NEW;
END
$guard$;

-- Defensive: this trigger function has no intended direct API callers.
REVOKE ALL ON FUNCTION public.pipo_global_v1_prevent_currency_relabel()
    FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS pipo_global_v1_immutable_currency
    ON public.saving_goals;

CREATE TRIGGER pipo_global_v1_immutable_currency
    BEFORE UPDATE OF currency_code ON public.saving_goals
    FOR EACH ROW
    EXECUTE FUNCTION public.pipo_global_v1_prevent_currency_relabel();

COMMIT;
