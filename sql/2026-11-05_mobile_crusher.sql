-- Mobile crusher: excavator buckets in, loader buckets and truck loads out, one device logging
-- both sides. Its own tables and functions, with nothing shared with shifts, loads or milled:
-- crusher tonnes must never reach the ROM pad, COS or mill figures, and nothing here can touch
-- sync_party or active_shift.
--
-- Unlike the original tables, these are not open to the publishable key. anon holds no table
-- grants at all and reaches them only through the functions below, which is the arrangement the
-- README describes as the one the older tables should have.
--
-- Safe to run more than once. To remove the feature's data entirely:
--   drop function public.crusher_sync, public.crusher_active, public.crusher_summaries, public.crusher_range,
--                 public.crusher_downtime_sync, public.crusher_downtime_range;
--   drop table public.crusher_downtime, public.crusher_taps, public.crusher_shifts;

-- 1. Tables --------------------------------------------------------------------------------
create table if not exists public.crusher_shifts (
  id          uuid primary key default gen_random_uuid(),
  shift_date  date not null,
  shift_name  text not null check (shift_name in ('Day','Night')),
  started_at  timestamptz not null,
  -- capacity and fill per machine: {"excavator":{"cap":12,"fill":0.9},...}. These are the current
  -- settings only. Each tap keeps the tonnes it was logged with, so changing one never rewrites
  -- what has already been counted.
  machines    jsonb not null default '{}'::jsonb,
  device      text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (shift_date, shift_name)
);

create table if not exists public.crusher_taps (
  id          uuid primary key,
  shift_id    uuid not null references public.crusher_shifts(id) on delete cascade,
  logged_at   timestamptz not null,
  machine     text not null check (machine in ('excavator','loader','truck')),
  ore         text not null default '',
  tonnes      numeric not null check (tonnes >= 0 and tonnes <= 1000),
  device      text not null,
  created_at  timestamptz not null default now()
);
create index if not exists crusher_taps_shift_idx on public.crusher_taps (shift_id, logged_at);

-- A stop is entered whole, start and restart together, so the database cannot hold an open one.
-- The delay log removed from the main app in October failed on exactly that: stops left open ran
-- on and made every figure derived from them wrong. A stop crossing a changeover is stored as one
-- row per shift, which is what the twelve hour limit holds the page to.
create table if not exists public.crusher_downtime (
  id          uuid primary key,
  shift_id    uuid not null references public.crusher_shifts(id) on delete cascade,
  started_at  timestamptz not null,
  ended_at    timestamptz not null,
  reason      text not null check (length(reason) > 0),
  note        text not null default '',
  device      text not null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  check (ended_at > started_at and ended_at - started_at <= interval '12 hours')
);
create index if not exists crusher_downtime_shift_idx on public.crusher_downtime (shift_id, started_at);

alter table public.crusher_shifts   enable row level security;
alter table public.crusher_taps     enable row level security;
alter table public.crusher_downtime enable row level security;
revoke all on public.crusher_shifts   from anon, authenticated;
revoke all on public.crusher_taps     from anon, authenticated;
revoke all on public.crusher_downtime from anon, authenticated;

-- 2. Writing -------------------------------------------------------------------------------
-- p_taps is this device's whole copy of one shift: [{id, logged_at, machine, ore, tonnes}].
-- Rows are upserted and whatever this device has since deleted is pruned. Both are scoped to the
-- device, so a replacement pad with an empty log cannot wipe what the real one recorded, and one
-- device cannot overwrite another's rows.
-- Settings merge per machine and a device sends only machines it has complete, so a wiped pad
-- cannot blank them. A new shift starts from the shift before it.
create or replace function public.crusher_sync(p_date date, p_name text, p_device text,
                                               p_started_at timestamptz, p_machines jsonb, p_taps jsonb)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  sid uuid;
  prev jsonb;
  incoming jsonb := coalesce(p_machines,'{}'::jsonb);
  dev text := coalesce(p_device,'');
begin
  if dev = '' then raise exception 'crusher_sync needs a device name'; end if;

  select s.machines into prev from public.crusher_shifts s
   where s.started_at < p_started_at order by s.started_at desc limit 1;

  insert into public.crusher_shifts as s (shift_date, shift_name, started_at, machines, device)
  values (p_date, p_name, p_started_at, coalesce(prev,'{}'::jsonb) || incoming, dev)
  on conflict (shift_date, shift_name) do update
    set started_at = least(s.started_at, excluded.started_at),
        machines   = s.machines || incoming,
        device     = excluded.device,
        updated_at = now()
  returning s.id into sid;

  insert into public.crusher_taps as t (id, shift_id, logged_at, machine, ore, tonnes, device)
  select r.id, sid, r.logged_at, r.machine, coalesce(r.ore,''), r.tonnes, dev
    from jsonb_to_recordset(coalesce(p_taps,'[]'::jsonb))
      as r(id uuid, logged_at timestamptz, machine text, ore text, tonnes numeric)
  on conflict (id) do update
    set shift_id = excluded.shift_id, logged_at = excluded.logged_at, machine = excluded.machine,
        ore = excluded.ore, tonnes = excluded.tonnes
    where t.device = excluded.device;

  delete from public.crusher_taps t
   where t.shift_id = sid and t.device = dev
     and not exists (select 1 from jsonb_array_elements(coalesce(p_taps,'[]'::jsonb)) e
                      where (e->>'id')::uuid = t.id);

  return jsonb_build_object('shift_id', sid);
end
$function$;

-- Downtime for one shift: [{id, started_at, ended_at, reason, note, deleted}]. Only the rows sent
-- are touched, so unlike crusher_sync nothing is pruned and a replacement pad can correct a stop
-- it did not enter. A stop can come before the shift's first tap, so the shift is made if needed.
create or replace function public.crusher_downtime_sync(p_date date, p_name text, p_device text,
                                                        p_started_at timestamptz, p_rows jsonb)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  sid uuid;
  prev jsonb;
  dev text := coalesce(p_device,'');
begin
  if dev = '' then raise exception 'crusher_downtime_sync needs a device name'; end if;

  select s.machines into prev from public.crusher_shifts s
   where s.started_at < p_started_at order by s.started_at desc limit 1;

  insert into public.crusher_shifts as s (shift_date, shift_name, started_at, machines, device)
  values (p_date, p_name, p_started_at, coalesce(prev,'{}'::jsonb), dev)
  on conflict (shift_date, shift_name) do update
    set started_at = least(s.started_at, excluded.started_at), updated_at = now()
  returning s.id into sid;

  delete from public.crusher_downtime d
   using jsonb_array_elements(coalesce(p_rows,'[]'::jsonb)) e
   where d.id = (e->>'id')::uuid and coalesce((e->>'deleted')::boolean,false);

  insert into public.crusher_downtime as d (id, shift_id, started_at, ended_at, reason, note, device)
  select r.id, sid, r.started_at, r.ended_at, r.reason, coalesce(r.note,''), dev
    from jsonb_to_recordset(coalesce(p_rows,'[]'::jsonb))
      as r(id uuid, started_at timestamptz, ended_at timestamptz, reason text, note text, deleted boolean)
   where not coalesce(r.deleted,false)
  on conflict (id) do update
    set shift_id = excluded.shift_id, started_at = excluded.started_at, ended_at = excluded.ended_at,
        reason = excluded.reason, note = excluded.note, device = excluded.device, updated_at = now();

  return jsonb_build_object('shift_id', sid);
end
$function$;

-- 3. Reading -------------------------------------------------------------------------------
-- The most recently started shift with every tap, for the live screen.
create or replace function public.crusher_active()
 returns jsonb
 language sql
 stable
 security definer
 set search_path to ''
as $function$
  with s as (select * from public.crusher_shifts order by started_at desc limit 1)
  select case when not exists (select 1 from s) then jsonb_build_object('shift',null,'taps','[]'::jsonb)
  else jsonb_build_object(
    'shift', (select to_jsonb(s) from s),
    'taps', coalesce((select jsonb_agg(jsonb_build_object('id',t.id,'logged_at',t.logged_at,'machine',t.machine,
              'ore',t.ore,'tonnes',t.tonnes,'device',t.device) order by t.logged_at)
            from public.crusher_taps t where t.shift_id = (select id from s)),'[]'::jsonb))
  end;
$function$;

-- One row per shift, newest first, for Previous shifts.
create or replace function public.crusher_summaries(p_from date default null, p_to date default null, p_limit int default 120)
 returns jsonb
 language sql
 stable
 security definer
 set search_path to ''
as $function$
  select coalesce(jsonb_agg(x order by x.started_at desc),'[]'::jsonb) from (
    select s.id, s.shift_date, s.shift_name, s.started_at,
      count(t.id) filter (where t.machine='excavator') as in_n,
      coalesce(sum(t.tonnes) filter (where t.machine='excavator'),0) as in_t,
      count(t.id) filter (where t.machine='loader') as loader_n,
      coalesce(sum(t.tonnes) filter (where t.machine='loader'),0) as loader_t,
      count(t.id) filter (where t.machine='truck') as truck_n,
      coalesce(sum(t.tonnes) filter (where t.machine='truck'),0) as truck_t,
      max(t.logged_at) as last_tap,
      (select coalesce(sum(extract(epoch from (d.ended_at - d.started_at)) / 60),0)
         from public.crusher_downtime d where d.shift_id = s.id) as down_min
    from public.crusher_shifts s
    left join public.crusher_taps t on t.shift_id = s.id
    where (p_from is null or s.shift_date >= p_from) and (p_to is null or s.shift_date <= p_to)
    group by s.id
    order by s.started_at desc
    limit greatest(1, least(coalesce(p_limit,120), 500))
  ) x;
$function$;

-- Every tap in a date range, for the CSV exports.
create or replace function public.crusher_range(p_from date, p_to date)
 returns jsonb
 language sql
 stable
 security definer
 set search_path to ''
as $function$
  select coalesce(jsonb_agg(jsonb_build_object('shift_date',s.shift_date,'shift_name',s.shift_name,
           'logged_at',t.logged_at,'machine',t.machine,'ore',t.ore,'tonnes',t.tonnes,'device',t.device)
           order by t.logged_at),'[]'::jsonb)
    from public.crusher_taps t
    join public.crusher_shifts s on s.id = t.shift_id
   where s.shift_date between p_from and p_to;
$function$;

-- Every stop in a date range, for the downtime list and the CSV exports.
create or replace function public.crusher_downtime_range(p_from date, p_to date)
 returns jsonb
 language sql
 stable
 security definer
 set search_path to ''
as $function$
  select coalesce(jsonb_agg(jsonb_build_object('id',d.id,'shift_date',s.shift_date,'shift_name',s.shift_name,
           'started_at',d.started_at,'ended_at',d.ended_at,'reason',d.reason,'note',d.note,'device',d.device)
           order by d.started_at),'[]'::jsonb)
    from public.crusher_downtime d
    join public.crusher_shifts s on s.id = d.shift_id
   where s.shift_date between p_from and p_to;
$function$;

-- 4. Access --------------------------------------------------------------------------------
revoke all on function public.crusher_downtime_sync(date,text,text,timestamptz,jsonb) from public;
revoke all on function public.crusher_downtime_range(date,date) from public;
grant execute on function public.crusher_downtime_sync(date,text,text,timestamptz,jsonb) to anon, authenticated;
grant execute on function public.crusher_downtime_range(date,date) to anon, authenticated;
revoke all on function public.crusher_sync(date,text,text,timestamptz,jsonb,jsonb) from public;
revoke all on function public.crusher_active() from public;
revoke all on function public.crusher_summaries(date,date,int) from public;
revoke all on function public.crusher_range(date,date) from public;
grant execute on function public.crusher_sync(date,text,text,timestamptz,jsonb,jsonb) to anon, authenticated;
grant execute on function public.crusher_active() to anon, authenticated;
grant execute on function public.crusher_summaries(date,date,int) to anon, authenticated;
grant execute on function public.crusher_range(date,date) to anon, authenticated;
