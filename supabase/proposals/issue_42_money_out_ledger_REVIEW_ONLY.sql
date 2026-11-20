-- Pipo #42 proposed migration. REVIEW ONLY — NOT APPLIED TO LIVE SUPABASE.
-- The existing saving_transactions table remains the immutable positive-contribution journal.
-- All money-out entries go through public.record_money_out, never direct client INSERT.
create table if not exists public.saving_adjustments (
    id uuid primary key,
    goal_id uuid not null,
    user_id uuid not null references auth.users(id) on delete cascade,
    kind text not null check (kind in ('money_out', 'correction')),
    amount numeric(18,2) not null check (amount <> 0 and abs(amount) <= 9999999999999999),
    note text check (note is null or char_length(note) <= 240),
    preference text check (preference in ('keep_date','keep_amount')),
    corrects_event_id uuid references public.saving_adjustments(id),
    corrected_amount numeric(18,2),
    created_at timestamptz not null default now(),
    constraint adjustment_owned_goal foreign key (goal_id,user_id)
       references public.saving_goals(id,user_id) on delete cascade,
    constraint adjustment_kind_shape check (
       (kind = 'money_out' and amount > 0 and corrects_event_id is null and preference is not null and corrected_amount is null)
       or (kind = 'correction' and corrects_event_id is not null and preference is null and corrected_amount > 0)
    )
);
create index if not exists saving_adjustments_owner_goal_idx
    on public.saving_adjustments(user_id,goal_id,created_at,id);
alter table public.saving_adjustments enable row level security;
revoke all on public.saving_adjustments from public,anon,authenticated;
grant select on public.saving_adjustments to authenticated;
create policy saving_adjustments_owned_read on public.saving_adjustments
    for select to authenticated using ((select auth.uid()) = user_id);

-- A concurrent call for the same goal is serialized by a row lock.
-- The caller supplies a stable UUID across retries; a duplicate with different
-- payload is rejected, not silently treated as a successful new entry.
create or replace function public.record_money_out(
    p_id uuid, p_goal_id uuid, p_amount numeric, p_note text, p_preference text
)
returns public.saving_adjustments
language plpgsql security definer set search_path = ''
as $$
declare
    v_owner uuid;
    v_goal public.saving_goals%rowtype;
    v_prior public.saving_adjustments%rowtype;
    v_contributions numeric;
    v_out numeric;
    v_corrections numeric;
    v_record public.saving_adjustments%rowtype;
begin
    v_owner := auth.uid();
    if v_owner is null then
        raise exception 'Authentication required' using errcode = '28000';
    end if;
    if p_id is null or p_goal_id is null or p_amount is null
       or p_amount <= 0 or p_amount > 9999999999999999
       or p_amount <> trunc(p_amount, 2)
       or p_preference not in ('keep_date','keep_amount')
       or p_preference is null or char_length(coalesce(p_note,'')) > 240 then
        raise exception 'Invalid money-out entry' using errcode = '22023';
    end if;

    select * into v_goal from public.saving_goals
    where id = p_goal_id and user_id = v_owner for update;
    if not found then
        raise exception 'Goal unavailable' using errcode = '42501';
    end if;
    select * into v_prior from public.saving_adjustments where id = p_id;
    if found then
        if v_prior.user_id = v_owner and v_prior.goal_id = p_goal_id
           and v_prior.kind = 'money_out' and v_prior.amount = p_amount
           and v_prior.note is not distinct from nullif(btrim(p_note),'')
           and v_prior.preference = p_preference then
            return v_prior;
        end if;
        raise exception 'Conflicting idempotency key' using errcode = '23505';
    end if;

    select coalesce(sum(amount),0) into v_contributions
      from public.saving_transactions where goal_id = p_goal_id and user_id = v_owner;
    select coalesce(sum(amount) filter (where kind='money_out'),0),
           coalesce(sum(amount) filter (where kind='correction'),0)
      into v_out,v_corrections
      from public.saving_adjustments where goal_id = p_goal_id and user_id = v_owner;
    if p_amount > (v_contributions - v_out + v_corrections) then
        raise exception 'Insufficient recorded savings' using errcode = '22003';
    end if;
    insert into public.saving_adjustments
       (id,goal_id,user_id,kind,amount,note,preference)
    values (p_id,p_goal_id,v_owner,'money_out',p_amount,
            nullif(btrim(p_note),''),p_preference)
    returning * into v_record;
    return v_record;
end;
$$;
revoke all on function public.record_money_out(uuid,uuid,numeric,text,text) from public,anon;
grant execute on function public.record_money_out(uuid,uuid,numeric,text,text) to authenticated;

-- Corrections are append-only deltas, not replacement saving events.
-- A corrected money-out of 300 after originally recording 500 adds +200
-- to the net recorded balance. Original XP and contribution rows are untouched.
create or replace function public.correct_money_out(
    p_id uuid, p_original_id uuid, p_corrected_amount numeric, p_note text
)
returns public.saving_adjustments
language plpgsql security definer set search_path = ''
as $
declare
    v_owner uuid;
    v_original public.saving_adjustments%rowtype;
    v_prior public.saving_adjustments%rowtype;
    v_locked public.saving_goals%rowtype;
    v_previous_corrections numeric;
    v_old_effective numeric;
    v_delta numeric;
    v_contributions numeric;
    v_out numeric;
    v_corrections numeric;
    v_event public.saving_adjustments%rowtype;
begin
    v_owner := auth.uid();
    if v_owner is null then
        raise exception 'Authentication required' using errcode = '28000';
    end if;
    if p_id is null or p_original_id is null or p_corrected_amount is null
       or p_corrected_amount <= 0 or p_corrected_amount > 9999999999999999
       or p_corrected_amount <> trunc(p_corrected_amount, 2)
       or char_length(coalesce(p_note,'')) > 240 then
        raise exception 'Invalid correction' using errcode = '22023';
    end if;
    select * into v_original from public.saving_adjustments
    where id = p_original_id and user_id = v_owner and kind='money_out';
    if not found then
        raise exception 'Original entry unavailable' using errcode = '42501';
    end if;
    select * into v_locked from public.saving_goals
    where id = v_original.goal_id and user_id = v_owner for update;
    if not found then
        raise exception 'Goal unavailable' using errcode = '42501';
    end if;

    select * into v_prior from public.saving_adjustments where id = p_id;
    if found then
        if v_prior.user_id = v_owner
           and v_prior.goal_id = v_original.goal_id
           and v_prior.kind = 'correction'
           and v_prior.corrects_event_id = p_original_id
           and v_prior.note is not distinct from nullif(btrim(p_note),'')
           and v_prior.corrected_amount = p_corrected_amount then
            return v_prior;
        end if;
        raise exception 'Conflicting correction idempotency key' using errcode = '23505';
    end if;

    select coalesce(sum(amount),0) into v_previous_corrections
       from public.saving_adjustments
       where corrects_event_id = p_original_id and user_id = v_owner;
    v_old_effective := v_original.amount - v_previous_corrections;
    v_delta := v_old_effective - p_corrected_amount;
    if v_delta = 0 then
        raise exception 'No correction required' using errcode = '22023';
    end if;
    select coalesce(sum(amount),0) into v_contributions
      from public.saving_transactions where goal_id = v_original.goal_id
      and user_id = v_owner;
    select coalesce(sum(amount) filter (where kind='money_out'),0),
           coalesce(sum(amount) filter (where kind='correction'),0)
      into v_out,v_corrections
      from public.saving_adjustments
      where goal_id = v_original.goal_id and user_id = v_owner;
    if v_contributions - v_out + v_corrections + v_delta < 0 then
        raise exception 'Correction exceeds available balance' using errcode = '22003';
    end if;
    insert into public.saving_adjustments
       (id,goal_id,user_id,kind,amount,note,corrects_event_id,corrected_amount)
    values (p_id,v_original.goal_id,v_owner,'correction',v_delta,
            nullif(btrim(p_note),''),p_original_id,p_corrected_amount)
    returning * into v_event;
    return v_event;
end;
$;
revoke all on function public.correct_money_out(uuid,uuid,numeric,text) from public,anon;
grant execute on function public.correct_money_out(uuid,uuid,numeric,text) to authenticated;

-- Still a design proposal. Client direct INSERT, UPDATE, DELETE remains revoked.
-- Security reviewer must validate correction idempotency with intervening edits,
-- account isolation, and migrations on a disposable test project before applying.
