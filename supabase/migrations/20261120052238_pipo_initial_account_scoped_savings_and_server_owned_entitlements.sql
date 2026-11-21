-- Pipo initial private-by-default application backend.
-- Only self-reported savings: no bank transfers, stored value or payments.
-- Goal and transaction data stay separate from server-owned entitlements.

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create table public.saving_goals (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid()
    references auth.users(id) on delete cascade,
  title text not null check (length(btrim(title)) between 1 and 120),
  category text not null default 'other'
    check (category in ('gadget','trip','gift','debt','automotive','house','other')),
  custom_category text
    check (custom_category is null or length(btrim(custom_category)) between 1 and 80),
  target_amount numeric(15,2) not null check (target_amount > 0),
  start_date timestamptz not null default now(),
  target_date timestamptz not null,
  rhythm text not null default 'weekly'
    check (rhythm in ('daily','weekly','biWeekly','monthly','flexible')),
  preferred_saving_day smallint
    check (preferred_saving_day is null or preferred_saving_day between 1 and 31),
  planned_contribution_override numeric(15,2)
    check (planned_contribution_override is null or planned_contribution_override > 0),
  currency_code char(3) not null default 'IDR'
    check (currency_code ~ '^[A-Z]{3}$'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint goal_target_after_start check (target_date >= start_date),
  constraint saving_goals_id_user_unique unique (id, user_id)
);

create index saving_goals_user_created_idx
  on public.saving_goals (user_id, created_at desc);

create table public.saving_transactions (
  id uuid primary key default gen_random_uuid(),
  goal_id uuid not null,
  user_id uuid not null default auth.uid()
    references auth.users(id) on delete cascade,
  amount numeric(15,2) not null check (amount > 0),
  xp_earned integer not null default 0 check (xp_earned between 0 and 100000),
  date timestamptz not null default now(),
  created_at timestamptz not null default now(),
  constraint saving_transaction_owned_goal foreign key (goal_id, user_id)
    references public.saving_goals (id, user_id) on delete cascade
);

create index saving_transactions_owner_goal_date_idx
  on public.saving_transactions (user_id, goal_id, date desc);

-- Server-owned purchase counts. Clients may read their own values but
-- NEVER create or modify them. Actual Apple purchase verification is not
-- implemented by this migration, so no client-authoritative paid grants exist.
create table public.user_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  purchased_personal_slots integer not null default 0
    check (purchased_personal_slots >= 0),
  purchased_group_slots integer not null default 0
    check (purchased_group_slots >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Seed read-only zero-entitlement profile records on Auth signup.
-- The trigger is private, not available as a client RPC.
create function private.pipo_seed_profile()
returns trigger
language plpgsql
security definer
set search_path = ''
as $pipo$
begin
  insert into public.user_profiles (user_id) values (new.id)
    on conflict (user_id) do nothing;
  return new;
end;
$pipo$;

revoke all on function private.pipo_seed_profile() from public, anon, authenticated;

create trigger pipo_profile_after_auth_signup
after insert on auth.users
for each row execute function private.pipo_seed_profile();

-- Works for any valid accounts created before this migration as well.
insert into public.user_profiles (user_id)
  select id from auth.users
  on conflict (user_id) do nothing;

-- Enable RLS first. Explicit grants required on new Supabase projects.
alter table public.saving_goals enable row level security;
alter table public.saving_transactions enable row level security;
alter table public.user_profiles enable row level security;

revoke all on public.saving_goals from public, anon, authenticated;
revoke all on public.saving_transactions from public, anon, authenticated;
revoke all on public.user_profiles from public, anon, authenticated;

grant select, insert, update, delete on public.saving_goals to authenticated;
grant select, insert, update, delete on public.saving_transactions to authenticated;
grant select on public.user_profiles to authenticated;

grant all on public.saving_goals, public.saving_transactions, public.user_profiles to service_role;

create policy pipo_goals_select_own on public.saving_goals
  for select to authenticated
  using ((select auth.uid()) = user_id);
create policy pipo_goals_insert_own on public.saving_goals
  for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy pipo_goals_update_own on public.saving_goals
  for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
create policy pipo_goals_delete_own on public.saving_goals
  for delete to authenticated
  using ((select auth.uid()) = user_id);

create policy pipo_transactions_select_own on public.saving_transactions
  for select to authenticated
  using ((select auth.uid()) = user_id);
create policy pipo_transactions_insert_own on public.saving_transactions
  for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy pipo_transactions_update_own on public.saving_transactions
  for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
create policy pipo_transactions_delete_own on public.saving_transactions
  for delete to authenticated
  using ((select auth.uid()) = user_id);

create policy pipo_profiles_select_own on public.user_profiles
  for select to authenticated
  using ((select auth.uid()) = user_id);

comment on table public.saving_goals is
  'Account-owned self-reported saving goals. Personal only; no shared/group membership or real money movement.';
comment on table public.saving_transactions is
  'Self-reported saving entries referencing a goal owned by the same account; not bank-verified transfers.';
comment on table public.user_profiles is
  'Server-owned purchased slot balances; authenticated clients have SELECT-only with RLS. No Apple verification yet.';
