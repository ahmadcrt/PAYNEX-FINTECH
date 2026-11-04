-- PAYNEX FINTECH: Supabase schema (DEMO ONLY, fictional money)
-- Run in Supabase Dashboard > SQL Editor.

create table public.profiles (
  id uuid primary key references auth.users on delete cascade,
  email text not null, name text not null, phone text default '',
  role text not null default 'user' check (role in ('user','admin')),
  status text not null default 'active' check (status in ('active','suspended')),
  acct text not null unique default ('PNX-' || (1000000000 + floor(random()*8999999999))::bigint),
  prefs jsonb not null default '{"email":true,"sms":false,"promo":false}',
  tfa boolean not null default false,
  card_num text not null, card_exp text not null default '09/29', card_frozen boolean not null default false,
  created_at timestamptz not null default now()
);

create table public.transactions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles on delete cascade,
  type text not null check (type in ('Transfer','Airtime','Bill','Savings','Income','Card')),
  title text not null, amount numeric(12,2) not null,
  status text not null default 'Completed' check (status in ('Completed','Flagged')),
  note text default '', ref text not null default upper(substr(md5(random()::text),1,8)),
  created_at timestamptz not null default now()
);

create table public.goals (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles on delete cascade,
  name text not null check (char_length(name) between 2 and 40),
  target numeric(12,2) not null check (target > 0),
  saved numeric(12,2) not null default 0,
  created_at timestamptz not null default now()
);

create table public.goal_deposits (
  id uuid primary key default gen_random_uuid(),
  goal_id uuid not null references public.goals on delete cascade,
  user_id uuid not null references public.profiles on delete cascade,
  amount numeric(12,2) not null check (amount > 0),
  created_at timestamptz not null default now()
);

create table public.activity_log (
  id bigint generated always as identity primary key,
  message text not null, created_at timestamptz not null default now()
);

create index on public.transactions (user_id, created_at desc);

-- Helpers
create function public.is_admin() returns boolean language sql security definer stable
set search_path = public as $$ select exists(select 1 from profiles where id = auth.uid() and role = 'admin' and status = 'active') $$;

create function public.balance(uid uuid) returns numeric language sql security definer stable
set search_path = public as $$ select coalesce(sum(amount),0) from transactions where user_id = uid and status = 'Completed' $$;

-- New user: profile, demo card, $5,000 demo credit
create function public.handle_new_user() returns trigger language plpgsql security definer
set search_path = public as $$
begin
  insert into profiles (id, email, name, card_num)
  values (new.id, new.email, coalesce(nullif(trim(new.raw_user_meta_data->>'name'),''), 'Demo User'),
    '5300 ' || lpad(floor(random()*10000)::text,4,'0') || ' ' || lpad(floor(random()*10000)::text,4,'0') || ' ' || lpad(floor(random()*10000)::text,4,'0'));
  insert into transactions (user_id, type, title, amount) values (new.id, 'Income', 'Welcome demo credit', 5000);
  return new;
end $$;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();

-- Block self-promotion: only admins may change role/status
create function public.guard_profile() returns trigger language plpgsql as $$
begin
  if not public.is_admin() and (new.role <> old.role or new.status <> old.status or new.email <> old.email or new.acct <> old.acct) then
    raise exception 'Not allowed';
  end if;
  return new;
end $$;
create trigger guard_profile before update on public.profiles for each row execute function public.guard_profile();

-- Row Level Security
alter table profiles enable row level security;
alter table transactions enable row level security;
alter table goals enable row level security;
alter table goal_deposits enable row level security;
alter table activity_log enable row level security;

create policy "own or admin read" on profiles for select using (id = auth.uid() or is_admin());
create policy "own update" on profiles for update using (id = auth.uid() or is_admin()) with check (id = auth.uid() or is_admin());
create policy "own or admin read" on transactions for select using (user_id = auth.uid() or is_admin());
create policy "admin moderate" on transactions for update using (is_admin()) with check (is_admin());
create policy "own goals read" on goals for select using (user_id = auth.uid());
create policy "own goals insert" on goals for insert with check (user_id = auth.uid());
create policy "own deposits read" on goal_deposits for select using (user_id = auth.uid());
create policy "admin read log" on activity_log for select using (is_admin());
-- No client INSERT policy on transactions or deposits: money moves only through the functions below.

-- Demo money movement (security definer, validated server-side)
create function public.demo_transfer(recipient text, recipient_name text, amt numeric, memo text default '')
returns uuid language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); r profiles; tid uuid;
begin
  if me is null then raise exception 'Sign in required'; end if;
  if amt is null or amt <= 0 or amt > 10000 then raise exception 'Invalid amount'; end if;
  if amt > balance(me) then raise exception 'Insufficient demo balance'; end if;
  select * into r from profiles where lower(email) = lower(recipient) or acct = recipient;
  if r.id = me then raise exception 'Cannot send to yourself'; end if;
  insert into transactions (user_id,type,title,amount,note) values (me,'Transfer','To '||recipient_name,-amt,memo) returning id into tid;
  if r.id is not null then insert into transactions (user_id,type,title,amount,note) values (r.id,'Income','From '||(select name from profiles where id=me),amt,memo); end if;
  insert into activity_log(message) values ('Transfer of '||amt||' by '||me);
  return tid;
end $$;

create function public.demo_pay(kind text, provider text, account text, amt numeric)
returns uuid language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); tid uuid;
begin
  if kind not in ('Airtime','Bill') then raise exception 'Invalid payment type'; end if;
  if amt < 1 or amt > balance(me) then raise exception 'Invalid amount or insufficient balance'; end if;
  if (select card_frozen from profiles where id = me) then raise exception 'Card is frozen'; end if;
  insert into transactions (user_id,type,title,amount,note) values (me,kind,provider,-amt,'Account '||account) returning id into tid;
  return tid;
end $$;

create function public.demo_save(goal uuid, amt numeric) returns void
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); g goals;
begin
  select * into g from goals where id = goal and user_id = me;
  if g.id is null then raise exception 'Goal not found'; end if;
  if amt <= 0 or amt > balance(me) then raise exception 'Invalid amount or insufficient balance'; end if;
  update goals set saved = saved + amt where id = goal;
  insert into goal_deposits(goal_id,user_id,amount) values (goal,me,amt);
  insert into transactions(user_id,type,title,amount) values (me,'Savings','Savings: '||g.name,-amt);
end $$;

revoke all on function public.demo_transfer, public.demo_pay, public.demo_save from public, anon;
grant execute on function public.demo_transfer, public.demo_pay, public.demo_save to authenticated;

-- To make yourself admin after signing up (run in SQL Editor, which bypasses RLS):
-- update public.profiles set role = 'admin' where email = 'you@example.com';
