-- PAYNEX schema v2: tighter permissions. Run AFTER schema.sql.
-- Run this, then deploy the matching index.html straight away: admin buttons now use the functions below.

alter table public.profiles force row level security;
alter table public.transactions force row level security;
alter table public.goals force row level security;
alter table public.goal_deposits force row level security;
alter table public.activity_log force row level security;

-- Anonymous visitors get no table access at all
revoke all on public.profiles, public.transactions, public.goals, public.goal_deposits, public.activity_log from anon;

-- Signed-in users: money records change only through server-side functions
revoke insert, update, delete on public.transactions, public.goal_deposits, public.activity_log from authenticated;
revoke update, delete on public.goals from authenticated;
revoke insert on public.goals from authenticated;
grant insert (user_id, name, target) on public.goals to authenticated;

-- Profiles: users may edit only their own non-sensitive columns
revoke update, delete on public.profiles from authenticated;
grant update (name, phone, prefs, tfa, card_frozen) on public.profiles to authenticated;
drop policy if exists "own update" on public.profiles;
create policy "own update" on public.profiles for update using (id = auth.uid()) with check (id = auth.uid());
drop policy if exists "admin moderate" on public.transactions;

-- Close a leak: balance(uuid) must not be callable by clients (it is used only inside the demo_* functions)
revoke execute on function public.balance(uuid) from public, anon, authenticated;

-- Admin actions: validated, role-checked and logged
create or replace function public.admin_set_user_status(uid uuid, new_status text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'Not allowed'; end if;
  if new_status not in ('active','suspended') then raise exception 'Invalid status'; end if;
  if (select role from profiles where id = uid) = 'admin' then raise exception 'Admins cannot be changed here'; end if;
  update profiles set status = new_status where id = uid;
  insert into activity_log(message) values ('Admin set user ' || uid || ' to ' || new_status);
end $$;

create or replace function public.admin_set_tx_status(tid uuid, new_status text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'Not allowed'; end if;
  if new_status not in ('Completed','Flagged') then raise exception 'Invalid status'; end if;
  update transactions set status = new_status where id = tid;
  insert into activity_log(message) values ('Admin set transaction ' || tid || ' to ' || new_status);
end $$;

revoke all on function public.admin_set_user_status, public.admin_set_tx_status from public, anon;
grant execute on function public.admin_set_user_status, public.admin_set_tx_status to authenticated;
