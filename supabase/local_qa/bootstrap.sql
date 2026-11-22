-- Pipo Global Experience V1 — disposable local PostgreSQL bootstrap.
-- This is an isolated test database. Never point this script at Supabase production.
-- Requires superuser privileges only inside the ephemeral postgres:17 CI container.
\set ON_ERROR_STOP on

CREATE ROLE anon NOLOGIN;
CREATE ROLE authenticated NOLOGIN;
CREATE ROLE service_role NOLOGIN;

CREATE SCHEMA auth;
CREATE TABLE auth.users (
    id uuid PRIMARY KEY
);

-- Supabase auth.uid() reads the authenticated JWT subject. In this SQL-only
-- harness the subject is simulated with a test-only session setting; this
-- validates RLS semantics, NOT real JWT verification or the Auth REST service.
CREATE FUNCTION auth.uid()
RETURNS uuid
LANGUAGE sql STABLE SECURITY INVOKER
AS $auth$
    SELECT nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
$auth$;

GRANT USAGE ON SCHEMA auth TO authenticated;
GRANT EXECUTE ON FUNCTION auth.uid() TO authenticated;
GRANT USAGE ON SCHEMA public TO authenticated;

-- Exact first migration SQL extracted read-only from deployed Supabase
-- migration version 20261120052238. No production connection or data.
\ir 20261120052238_verified_schema_snapshot.sql

-- Verify the mirrored database has the owner-scoped schema we intend to test.
DO $assert$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'public' AND c.relname = 'saving_goals'
          AND c.relrowsecurity
    ) OR NOT EXISTS (
        SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'public' AND c.relname = 'saving_transactions'
          AND c.relrowsecurity
    ) THEN
        RAISE EXCEPTION 'FAIL: expected owner-scoped saving table RLS is missing';
    END IF;
END $assert$;
\echo 'PASS: original migration schema and RLS loaded into disposable local PostgreSQL'
