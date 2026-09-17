-- Corrections from the office, and a live shift that cannot be stuck as ended.
--
-- 1. A load can be corrected in the database and stay corrected.
--    The pad owns its rows and re-sends its own copy of every load on each sync, so an edit
--    made here used to last only until the next tip. `loads.corrected_at` marks a row whose
--    time, ore and tonnage were set here on purpose: sync_party keeps those three while the
--    pad is still sending the old values, and clears the mark the first time the pad sends
--    values that match — which a current page does by adopting the correction on its next
--    poll. From then on the pad owns the row again and its own edits flow as before.
--
--    First used on 17 Sep: thirteen loads tapped in 33 seconds at 07:28, catching up an hour
--    no one had been at the pad for, spread back across 06:30 to 07:30.
--
-- 2. A pad that is logging can clear a stale end time.
--    ended_at was only ever set, never cleared, so End shift followed by New shift left the
--    shift marked as ended while trucks kept tipping into it — the dashboard froze elapsed at
--    the end time and reported thousands of t/h. A pad contributing loads or delays now speaks
--    for ended_at the way it already speaks for the shift's settings; a silent pad still
--    cannot touch it.
--
-- Safe to run more than once.

alter table public.loads add column if not exists corrected_at timestamptz;

create or replace function public.sync_party(p_site text, p_date date, p_name text, p_party text, p_settings jsonb, p_loads jsonb, p_delays jsonb)
 returns jsonb
 language plpgsql
 set search_path to ''
as $function$
declare
  sid uuid;
  ts  timestamptz;
  dev text := coalesce(p_settings->>'device','');
  earliest timestamptz;
  has_rows boolean;
  pv public.shifts%rowtype;
  v_payload numeric; v_fill numeric; v_trucks int; v_exc int; v_ldr int;
  v_target numeric; v_hours numeric;
  foreign_loads int; foreign_delays int;
begin
  if p_party not in ('rom','cos') then
    raise exception 'unknown party %', p_party;
  end if;

  has_rows := coalesce(jsonb_array_length(p_loads), 0) > 0
           or coalesce(jsonb_array_length(p_delays), 0) > 0;

  select * into pv from public.shifts s
   where s.site = p_site
     and (s.shift_date, (s.shift_name = 'Night')) < (p_date, (p_name = 'Night'))
   order by s.shift_date desc, (s.shift_name = 'Night') desc
   limit 1;

  if has_rows then
    v_payload := coalesce((p_settings->>'payload')::numeric, pv.payload, 30);
    v_fill    := coalesce((p_settings->>'fill')::numeric, pv.fill, 0.9);
    v_trucks  := coalesce((p_settings->>'trucks')::int, pv.trucks, 0);
    v_exc     := coalesce((p_settings->>'excavators')::int, pv.excavators, 0);
    v_ldr     := coalesce((p_settings->>'loaders')::int, pv.loaders, 0);
    v_target  := coalesce((p_settings->>'target_tph')::numeric, pv.target_tph, 0);
    v_hours   := coalesce((p_settings->>'shift_hours')::numeric, pv.shift_hours, 12);
  else
    v_payload := coalesce(pv.payload, (p_settings->>'payload')::numeric, 30);
    v_fill    := coalesce(pv.fill, (p_settings->>'fill')::numeric, 0.9);
    v_trucks  := coalesce(pv.trucks, (p_settings->>'trucks')::int, 0);
    v_exc     := coalesce(pv.excavators, (p_settings->>'excavators')::int, 0);
    v_ldr     := coalesce(pv.loaders, (p_settings->>'loaders')::int, 0);
    v_target  := coalesce(pv.target_tph, (p_settings->>'target_tph')::numeric, 0);
    v_hours   := coalesce(pv.shift_hours, (p_settings->>'shift_hours')::numeric, 12);
  end if;

  insert into public.shifts (id, site, shift_date, shift_name, label, payload, fill,
                             trucks, excavators, loaders, target_tph, shift_hours, device,
                             started_at)
  values (gen_random_uuid(), p_site, p_date, p_name,
          coalesce(p_settings->>'label',''),
          v_payload, v_fill, v_trucks, v_exc, v_ldr, v_target, v_hours,
          nullif(dev,''),
          nullif(p_settings->>'started_at','')::timestamptz)
  on conflict (site, shift_date, shift_name) do update set
    label       = coalesce(nullif(excluded.label,''), public.shifts.label),
    payload     = case when has_rows then excluded.payload     else public.shifts.payload     end,
    fill        = case when has_rows then excluded.fill        else public.shifts.fill        end,
    trucks      = case when has_rows then excluded.trucks      else public.shifts.trucks      end,
    excavators  = case when has_rows then excluded.excavators  else public.shifts.excavators  end,
    loaders     = case when has_rows then excluded.loaders     else public.shifts.loaders     end,
    target_tph  = case when has_rows then excluded.target_tph  else public.shifts.target_tph  end,
    shift_hours = case when has_rows then excluded.shift_hours else public.shifts.shift_hours end
  returning id into sid;

  select count(*) into foreign_loads
    from jsonb_array_elements(coalesce(p_loads, '[]'::jsonb)) e
    join public.loads l on l.id = (e->>'id')::uuid
   where l.party <> p_party;

  select count(*) into foreign_delays
    from jsonb_array_elements(coalesce(p_delays, '[]'::jsonb)) e
    join public.delays d on d.id = (e->>'id')::uuid
   where d.party <> p_party;

  -- A corrected row keeps its time, ore and tonnage against a pad still sending the old ones,
  -- and hands ownership back the first time the pad's copy matches. SET expressions read the
  -- row as it was, so the comparison is against the corrected values.
  insert into public.loads (id, shift_id, party, device, logged_at, ore, tonnes, trucks, excavators, loaders)
  select (e->>'id')::uuid, sid, p_party, nullif(dev,''), (e->>'logged_at')::timestamptz,
         coalesce(e->>'ore',''), coalesce((e->>'tonnes')::numeric, 0),
         (e->>'trucks')::int, (e->>'excavators')::int, (e->>'loaders')::int
    from jsonb_array_elements(coalesce(p_loads, '[]'::jsonb)) e
  on conflict (id) do update set
    logged_at = case when public.loads.corrected_at is null then excluded.logged_at else public.loads.logged_at end,
    ore       = case when public.loads.corrected_at is null then excluded.ore       else public.loads.ore       end,
    tonnes    = case when public.loads.corrected_at is null then excluded.tonnes    else public.loads.tonnes    end,
    trucks = excluded.trucks, excavators = excluded.excavators, loaders = excluded.loaders,
    corrected_at = case
      when public.loads.corrected_at is not null
       and date_trunc('milliseconds', excluded.logged_at) = date_trunc('milliseconds', public.loads.logged_at)
       and excluded.ore = public.loads.ore
       and excluded.tonnes = public.loads.tonnes
      then null
      else public.loads.corrected_at end
  where public.loads.party = excluded.party;        -- never across parties

  delete from public.loads l
   where l.shift_id = sid and l.party = p_party and coalesce(l.device,'') = dev
     and not exists (select 1 from jsonb_array_elements(coalesce(p_loads, '[]'::jsonb)) e
                      where (e->>'id')::uuid = l.id);

  insert into public.delays (id, shift_id, party, device, started_at, ended_at, reason)
  select (e->>'id')::uuid, sid, p_party, nullif(dev,''), (e->>'started_at')::timestamptz,
         nullif(e->>'ended_at','')::timestamptz, coalesce(e->>'reason','')
    from jsonb_array_elements(coalesce(p_delays, '[]'::jsonb)) e
  on conflict (id) do update set
    started_at = excluded.started_at, ended_at = excluded.ended_at, reason = excluded.reason
  where public.delays.party = excluded.party;

  delete from public.delays d
   where d.shift_id = sid and d.party = p_party and coalesce(d.device,'') = dev
     and not exists (select 1 from jsonb_array_elements(coalesce(p_delays, '[]'::jsonb)) e
                      where (e->>'id')::uuid = d.id);

  select least(min(l.logged_at), min(d.started_at))
    into earliest
    from public.loads l
    full join public.delays d on d.shift_id = l.shift_id
   where coalesce(l.shift_id, d.shift_id) = sid;

  update public.shifts
     set started_at = least(public.shifts.started_at, earliest),
         ended_at   = case
                        when has_rows then nullif(p_settings->>'ended_at','')::timestamptz
                        when (p_settings->>'ended_at') is not null then (p_settings->>'ended_at')::timestamptz
                        else ended_at end,
         updated_at = now()
   where id = sid
  returning updated_at into ts;

  return jsonb_build_object('shift_id', sid, 'updated_at', ts,
                            'rejected_loads', foreign_loads, 'rejected_delays', foreign_delays);
end;
$function$;

notify pgrst, 'reload schema';
