-- A mill figure that was spread from a shift total says so.
--
-- The mill readings are hourly rates, and the hour-by-hour comparison against what was tipped
-- is the thing they are for. When nobody was there to read the meter each hour, a shift total
-- entered afterwards still has to go in as hours — but twelve identical hours are not twelve
-- readings, and a chart drawn from them would show the mill running dead flat all shift.
--
-- So the row carries a flag. Hours typed against the clock are readings; hours derived from a
-- total are marked estimated, and the app says so wherever it shows them.

alter table public.milled add column if not exists estimated boolean not null default false;

-- sync_milled: carry the flag in, defaulting to a reading when the pad does not send one, so an
-- older build that knows nothing about this keeps working exactly as it did.
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
    select distinct on (hour_start) hour_start, tonnes, estimated
      from (select (e->>'hour_start')::timestamptz      as hour_start,
                   (e->>'tonnes')::numeric              as tonnes,
                   coalesce((e->>'estimated')::boolean, false) as estimated
              from jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) e
             where e ? 'hour_start') x
     order by hour_start
  ), up as (
    insert into public.milled (shift_id, hour_start, tonnes, estimated, device)
    select sid, hour_start, greatest(tonnes, 0), estimated, nullif(dev,'')
      from src where tonnes is not null
    on conflict (shift_id, hour_start) do update
      set tonnes = excluded.tonnes, estimated = excluded.estimated,
          device = excluded.device, updated_at = now()
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

-- shift_detail: hand the flag back with the row.
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
                                   'tonnes', m.tonnes, 'estimated', m.estimated,
                                   'device', m.device, 'updated_at', m.updated_at)
                                 order by m.hour_start)
                          from public.milled m where m.shift_id = s.id), '[]'::jsonb)
  )
  from public.shifts s
 where s.id = p_id;
$function$;
