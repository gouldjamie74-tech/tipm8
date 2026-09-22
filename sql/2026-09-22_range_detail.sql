-- Everything in a date range, in one call.
--
-- shift_detail answers for one shift, which is right for opening a shift on screen but wrong
-- for an export: a month is sixty round trips, each one a chance for the pad's connection to
-- drop halfway through. This returns the loads, delays and mill readings for a range together,
-- so the export is one request that either works or does not.
--
-- Read-only and security invoker, like the rest: it reads exactly what the anon key can already
-- read through the other functions, and adds no path to anything it could not.

create or replace function public.range_detail(p_site text, p_from date, p_to date)
returns jsonb
language sql
stable
set search_path = ''
as $function$
  select jsonb_build_object(
    'site', p_site, 'from', p_from, 'to', p_to,

    'shifts', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', s.id, 'shift_date', s.shift_date, 'shift_name', s.shift_name,
               'label', s.label, 'started_at', s.started_at, 'ended_at', s.ended_at,
               'payload', s.payload, 'fill', s.fill,
               'target_tph', s.target_tph, 'shift_hours', s.shift_hours)
             order by s.shift_date, (s.shift_name = 'Night'))
      from public.shifts s
      where s.site = p_site and s.shift_date between p_from and p_to), '[]'::jsonb),

    'loads', coalesce((
      select jsonb_agg(jsonb_build_object(
               'shift_date', s.shift_date, 'shift_name', s.shift_name, 'party', l.party,
               'logged_at', l.logged_at, 'ore', l.ore, 'tonnes', l.tonnes,
               'trucks', l.trucks, 'excavators', l.excavators, 'loaders', l.loaders,
               'device', l.device, 'corrected_at', l.corrected_at)
             order by l.logged_at)
      from public.loads l
      join public.shifts s on s.id = l.shift_id
      where s.site = p_site and s.shift_date between p_from and p_to), '[]'::jsonb),

    'delays', coalesce((
      select jsonb_agg(jsonb_build_object(
               'shift_date', s.shift_date, 'shift_name', s.shift_name, 'party', d.party,
               'started_at', d.started_at, 'ended_at', d.ended_at, 'reason', d.reason)
             order by d.started_at)
      from public.delays d
      join public.shifts s on s.id = d.shift_id
      where s.site = p_site and s.shift_date between p_from and p_to), '[]'::jsonb),

    'milled', coalesce((
      select jsonb_agg(jsonb_build_object(
               'shift_date', s.shift_date, 'shift_name', s.shift_name,
               'hour_start', m.hour_start, 'tonnes', m.tonnes)
             order by m.hour_start)
      from public.milled m
      join public.shifts s on s.id = m.shift_id
      where s.site = p_site and s.shift_date between p_from and p_to), '[]'::jsonb)
  );
$function$;

grant execute on function public.range_detail(text, date, date) to anon, authenticated, service_role;
