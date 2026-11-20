-- Read-only structural audit for the Pipo initial Supabase schema.
-- Run with a privileged DB auditor, not from the iOS client.
-- This does not substitute for two-account authenticated API tests.
select c.relname as table_name, c.relrowsecurity as rls_enabled
from pg_class c
where c.oid in (
  'public.saving_goals'::regclass,
  'public.saving_transactions'::regclass,
  'public.user_profiles'::regclass
);
select schemaname, tablename, policyname, roles, cmd, qual, with_check
from pg_policies
where schemaname='public' and tablename in (
  'saving_goals','saving_transactions','user_profiles'
)
order by tablename, cmd;
select table_name, grantee, privilege_type
from information_schema.role_table_grants
where table_schema='public'
  and table_name in ('saving_goals','saving_transactions','user_profiles')
  and grantee in ('anon','authenticated')
order by table_name,grantee,privilege_type;
select conname,pg_get_constraintdef(oid) as constraint_sql
from pg_constraint
where conrelid='public.saving_transactions'::regclass
  and conname='saving_transaction_owned_goal';
