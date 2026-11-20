-- Read-only metadata checks for the Pipo Supabase initial schema.
-- Run in Pipo's intended project, not as a substitute for JWT-based A/B tests.
select
  (select count(*) = 3 from pg_class c join pg_namespace n on n.oid=c.relnamespace
   where n.nspname='public' and c.relname in ('saving_goals','saving_transactions','user_profiles')
   and c.relkind='r' and c.relrowsecurity) as all_three_tables_have_rls,
  (select count(*) = 9 from pg_policies
   where schemaname='public'
   and tablename in ('saving_goals','saving_transactions','user_profiles')
   and roles @> array['authenticated']::name[]) as nine_owner_policies,
  (select count(*) = 2 from pg_policies
   where schemaname='public' and cmd='UPDATE'
   and tablename in ('saving_goals','saving_transactions')
   and qual like '%auth.uid()%' and with_check like '%auth.uid()%') as updates_check_owner,
  has_table_privilege('authenticated','public.user_profiles','SELECT') as owner_profile_read_grant,
  not has_table_privilege('authenticated','public.user_profiles','INSERT') as no_client_profile_insert,
  not has_table_privilege('authenticated','public.user_profiles','UPDATE') as no_client_profile_update,
  not has_table_privilege('authenticated','public.user_profiles','DELETE') as no_client_profile_delete,
  not has_table_privilege('anon','public.user_profiles','SELECT') as no_anonymous_profile_read,
  (select count(*) = 1 from pg_constraint
   where conrelid='public.saving_transactions'::regclass
   and conname='saving_transaction_owned_goal'
   and pg_get_constraintdef(oid) like '%FOREIGN KEY (goal_id, user_id)%') as transaction_goal_owner_fk,
  not has_function_privilege('authenticated','private.pipo_seed_profile()','EXECUTE') as no_client_private_trigger_call;
