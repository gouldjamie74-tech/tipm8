-- Milled tonnes: the mill's hourly throughput, entered on the COS pad and compared with
-- what was tipped to the COS over the same hours. The difference is what the COS stockpile
-- built or gave up.
--
-- Hours are clock hours, twelve to a shift, as the plant reports them and the paper sheets
-- record them: Day 06:00-18:00, Night 18:00-06:00. The client sends each hour's start; the
-- database never has to work out which hours belong to which shift.
--
-- Safe to run more than once. Nothing here changes sync_party, so logging carries on
-- untouched whether or not this has been applied, and a page that predates it simply never
-- asks for the new fields.

-- 1. The table ---------------------------------------------------------------------------
create table if not exists public.milled (
  id          uuid primary key default gen_random_uuid(),
  shift_id    uuid not null references public.shifts(id) on delete cascade,
  hour_start  timestamptz not null,
  tonnes      numeric not null check (tonnes >= 0),
  device      text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (shift_id, hour_start)
);

alter table public.milled enable row level security;

-- Same access as loads and delays, deliberately without TRUNCATE.
grant select, insert, update, delete on public.milled to anon, authenticated;

drop policy if exists milled_read   on public.milled;
drop policy if exists milled_insert on public.milled;
drop policy if exists milled_update on public.milled;
drop policy if exists milled_delete on public.milled;
create policy milled_read   on public.milled for select to anon, authenticated using (true);
create policy milled_insert on public.milled for insert to anon, authenticated with check (true);
create policy milled_update on public.milled for update to anon, authenticated using (true) with check (true);
create policy milled_delete on public.milled for delete to anon, authenticated using (true);

-- 2. Writing it --------------------------------------------------------------------------
-- p_rows: [{ hour_start: iso, tonnes: number | null }]. A number sets that hour, null clears
-- it. Only the hours sent are touched, so a pad with nothing to say cannot wipe what another
-- pad entered — the mistake sync_party had to be taught twice.
--
-- Milled tonnes can arrive before the first tip of a shift. Then there is no shift row yet,
-- so one is made, inheriting its settings from the shift before it exactly as sync_party
-- does for a pad that is not contributing loads.
create or replace function public.sync_milled(p_site text, p_date date, p_name text,
                                              p_settings jsonb, p_rows jsonb)
 returns jsonb
 language plpgsql
 set search_path to ''
as $function$
declare
  sid uuid;
  dev text := coalesce(p_settings->>'device','');
  pv public.shifts%rowtype;
  n_set int := 0;
  n_cleared int := 0;
begin
  select s.id into sid from public.shifts s
   where s.site = p_site and s.shift_date = p_date and s.shift_name = p_name;

  if sid is null then
    select * into pv from public.shifts s
     where s.site = p_site
       and (s.shift_date, (s.shift_name = 'Night')) < (p_date, (p_name = 'Night'))
     order by s.shift_date desc, (s.shift_name = 'Night') desc
     limit 1;

    insert into public.shifts (id, site, shift_date, shift_name, label, payload, fill,
                               trucks, excavators, loaders, target_tph, shift_hours,
                               device, started_at)
    values (gen_random_uuid(), p_site, p_date, p_name, '',
            coalesce(pv.payload, 30), coalesce(pv.fill, 0.9), coalesce(pv.trucks, 0),
            coalesce(pv.excavators, 0), coalesce(pv.loaders, 0), coalesce(pv.target_tph, 0),
            coalesce(pv.shift_hours, 12), nullif(dev,''),
            nullif(p_settings->>'started_at','')::timestamptz)
    on conflict (site, shift_date, shift_name) do nothing;

    select s.id into sid from public.shifts s
     where s.site = p_site and s.shift_date = p_date and s.shift_name = p_name;
  end if;

  with src as (
    select distinct on (hour_start) hour_start, tonnes
      from (select (e->>'hour_start')::timestamptz as hour_start,
                   (e->>'tonnes')::numeric         as tonnes
              from jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) e
             where e ? 'hour_start') x
     order by hour_start
  ), up as (
    insert into public.milled (shift_id, hour_start, tonnes, device)
    select sid, hour_start, greatest(tonnes, 0), nullif(dev,'') from src where tonnes is not null
    on conflict (shift_id, hour_start) do update
      set tonnes = excluded.tonnes, device = excluded.device, updated_at = now()
    returning 1
  )
  select count(*) into n_set from up;

  delete from public.milled m
   using (select (e->>'hour_start')::timestamptz as hour_start
            from jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) e
           where e ? 'hour_start' and (e->>'tonnes') is null) c
   where m.shift_id = sid and m.hour_start = c.hour_start;
  get diagnostics n_cleared = row_count;

  update public.shifts set updated_at = now() where id = sid;

  return jsonb_build_object('shift_id', sid, 'set', n_set, 'cleared', n_cleared);
end;
$function$;

grant execute on function public.sync_milled(text, date, text, jsonb, jsonb) to anon, authenticated;

-- 3. Reading it --------------------------------------------------------------------------
-- The three read functions keep their signatures and gain fields, so a page that predates
-- this ignores them.

-- active_shift: the live shift's milled hours, and the previous shift's milled total.
create or replace function public.active_shift(p_site text default 'rom'::text)
 returns jsonb
 language sql
 stable
 set search_path to ''
as $function$
  with pick as (
    select s.* from public.shifts s
     where s.site = p_site and s.started_at is not null
     order by s.started_at desc
     limit 1
  ),
  prior as (
    select s.* from public.shifts s, pick p
     where s.site = p_site and s.started_at is not null and s.id <> p.id
       and (s.shift_date, (s.shift_name = 'Night')) < (p.shift_date, (p.shift_name = 'Night'))
     order by s.shift_date desc, (s.shift_name = 'Night') desc
     limit 1
  )
  select jsonb_build_object(
    'shift',  to_jsonb(p),
    'loads',  coalesce((select jsonb_agg(to_jsonb(l) order by l.logged_at)
                          from public.loads l where l.shift_id = p.id), '[]'::jsonb),
    'delays', coalesce((select jsonb_agg(to_jsonb(d) order by d.started_at)
                          from public.delays d where d.shift_id = p.id), '[]'::jsonb),
    'milled', coalesce((select jsonb_agg(jsonb_build_object('hour_start', m.hour_start,
                                   'tonnes', m.tonnes, 'device', m.device,
                                   'updated_at', m.updated_at) order by m.hour_start)
                          from public.milled m where m.shift_id = p.id), '[]'::jsonb),
    'prev',   (select to_jsonb(q) || jsonb_build_object(
                        'rom_loads',  (select count(*)                  from public.loads l where l.shift_id=q.id and l.party='rom'),
                        'rom_tonnes', (select coalesce(sum(l.tonnes),0) from public.loads l where l.shift_id=q.id and l.party='rom'),
                        'cos_loads',  (select count(*)                  from public.loads l where l.shift_id=q.id and l.party='cos'),
                        'cos_tonnes', (select coalesce(sum(l.tonnes),0) from public.loads l where l.shift_id=q.id and l.party='cos'),
                        'first_load', (select min(l.logged_at) from public.loads l where l.shift_id=q.id),
                        'last_load',  (select max(l.logged_at) from public.loads l where l.shift_id=q.id),
                        'rom_delay_ms', (select coalesce(sum(extract(epoch from (coalesce(d.ended_at, now()) - d.started_at)) * 1000), 0)::bigint
                                           from public.delays d where d.shift_id=q.id and d.party='rom'),
                        'cos_delay_ms', (select coalesce(sum(extract(epoch from (coalesce(d.ended_at, now()) - d.started_at)) * 1000), 0)::bigint
                                           from public.delays d where d.shift_id=q.id and d.party='cos'),
                        'milled_tonnes', (select coalesce(sum(m.tonnes),0) from public.milled m where m.shift_id=q.id),
                        'milled_hours',  (select count(*)                  from public.milled m where m.shift_id=q.id))
                 from prior q),
    'open_shifts', (select count(*) from public.shifts x
                     where x.site = p_site and x.started_at is not null and x.ended_at is null)
  )
  from pick p;
$function$;

-- shift_summaries: milled total, how many hours it covers, and what was tipped to the COS in
-- those same hours — the only fair thing to hold a part-entered milled column against.
create or replace function public.shift_summaries(
  p_site  text default 'rom',
  p_from  date default null,
  p_to    date default null,
  p_limit int  default 60
) returns jsonb
 language sql
 stable
 set search_path to ''
as $function$
  select coalesce(jsonb_agg(to_jsonb(r) order by r.shift_date desc, r.night desc), '[]'::jsonb)
  from (
    select sh.id, sh.shift_date, sh.shift_name, sh.label,
           (sh.shift_name = 'Night') as night,
           sh.started_at, sh.ended_at, sh.payload, sh.fill,
           sh.target_tph, sh.shift_hours, sh.trucks, sh.excavators, sh.loaders,
           (select count(*)                   from public.loads l where l.shift_id=sh.id and l.party='rom') as rom_loads,
           (select coalesce(sum(l.tonnes),0)  from public.loads l where l.shift_id=sh.id and l.party='rom') as rom_tonnes,
           (select count(*)                   from public.loads l where l.shift_id=sh.id and l.party='cos') as cos_loads,
           (select coalesce(sum(l.tonnes),0)  from public.loads l where l.shift_id=sh.id and l.party='cos') as cos_tonnes,
           (select min(l.logged_at) from public.loads l where l.shift_id=sh.id) as first_load,
           (select max(l.logged_at) from public.loads l where l.shift_id=sh.id) as last_load,
           (select coalesce(sum(extract(epoch from (coalesce(d.ended_at, now()) - d.started_at)) * 1000), 0)::bigint
              from public.delays d where d.shift_id=sh.id and d.party='rom') as rom_delay_ms,
           (select coalesce(sum(extract(epoch from (coalesce(d.ended_at, now()) - d.started_at)) * 1000), 0)::bigint
              from public.delays d where d.shift_id=sh.id and d.party='cos') as cos_delay_ms,
           (select jsonb_object_agg(o.ore, o.t) from (
              select l.ore, sum(l.tonnes) as t from public.loads l
               where l.shift_id=sh.id and l.party='rom' and coalesce(l.ore,'') <> ''
               group by l.ore) o) as rom_by_ore,
           (select jsonb_object_agg(o.ore, o.t) from (
              select l.ore, sum(l.tonnes) as t from public.loads l
               where l.shift_id=sh.id and l.party='cos' and coalesce(l.ore,'') <> ''
               group by l.ore) o) as cos_by_ore,
           (select coalesce(sum(m.tonnes),0) from public.milled m where m.shift_id=sh.id) as milled_tonnes,
           (select count(*)                  from public.milled m where m.shift_id=sh.id) as milled_hours,
           (select coalesce(sum(l.tonnes),0)
              from public.milled m
              join public.loads l on l.shift_id = sh.id and l.party = 'cos'
                                 and l.logged_at >= m.hour_start
                                 and l.logged_at <  m.hour_start + interval '1 hour'
             where m.shift_id = sh.id) as milled_tipped
      from public.shifts sh
     where sh.site = p_site
       and sh.started_at is not null
       and (p_from is null or sh.shift_date >= p_from)
       and (p_to   is null or sh.shift_date <= p_to)
     order by sh.shift_date desc, (sh.shift_name = 'Night') desc
     limit greatest(coalesce(p_limit, 60), 1)
  ) r;
$function$;

-- shift_detail: a finished shift's milled hours, for its detail view and its CSV.
create or replace function public.shift_detail(p_id uuid)
 returns jsonb
 language sql
 stable
 set search_path to ''
as $function$
  select jsonb_build_object(
    'shift',  to_jsonb(s),
    'loads',  coalesce((select jsonb_agg(to_jsonb(l) order by l.logged_at, l.party)
                          from public.loads l where l.shift_id = s.id), '[]'::jsonb),
    'delays', coalesce((select jsonb_agg(to_jsonb(d) order by d.started_at, d.party)
                          from public.delays d where d.shift_id = s.id), '[]'::jsonb),
    'milled', coalesce((select jsonb_agg(jsonb_build_object('hour_start', m.hour_start,
                                   'tonnes', m.tonnes, 'device', m.device,
                                   'updated_at', m.updated_at) order by m.hour_start)
                          from public.milled m where m.shift_id = s.id), '[]'::jsonb)
  )
  from public.shifts s
 where s.id = p_id;
$function$;

-- Tell the API about the new function without waiting for its schema cache to notice.
notify pgrst, 'reload schema';
