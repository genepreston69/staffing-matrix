-- 0004_rpcs.sql — RPCs (called from React/Edge Function) + history trigger.

begin;

-- ---------------------------------------------------------------------------
-- daily_snapshot_history trigger — captures the row + its unit_daily_census
-- children whenever the snapshot is updated. Implements decision D6.
-- ---------------------------------------------------------------------------
create or replace function app.snapshot_history_capture() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_payload jsonb;
begin
  -- Capture the *previous* state before the update applies.
  select jsonb_build_object(
    'snapshot',  to_jsonb(old.*),
    'units', coalesce((
      select jsonb_agg(to_jsonb(udc.*) order by udc.unit_id)
      from public.unit_daily_census udc
      where udc.snapshot_id = old.id
    ), '[]'::jsonb)
  ) into v_payload;

  insert into public.daily_snapshot_history
    (snapshot_id, facility_id, time_entry_date, snapshot_data, changed_by)
  values
    (old.id, old.facility_id, old.time_entry_date, v_payload, auth.uid());

  return new;
end $$;

drop trigger if exists trg_snapshot_history on daily_snapshots;
create trigger trg_snapshot_history
  before update on daily_snapshots
  for each row execute function app.snapshot_history_capture();

-- ---------------------------------------------------------------------------
-- push_daily_snapshot — replaces the Power Automate webhook.
-- Accepts the same shape the prototype already builds (see
-- powerautomate-trigger-schema.json) but also accepts a normalized form:
--   {
--     facility_slug: 'highland',
--     time_entry_date: '2026-05-04',
--     np_model_pct: 12.6,
--     units: [ { key:'1East', census:16, obs_hours:25, obs_notes:'...' }, ... ]
--   }
--
-- Returns the snapshot_id. Upsert semantics: one snapshot per
-- (facility_id, time_entry_date); re-pushes update.
-- ---------------------------------------------------------------------------
create or replace function push_daily_snapshot(payload jsonb)
returns bigint
language plpgsql security invoker set search_path = public, app as $$
declare
  v_facility_id   bigint;
  v_facility_slug text := payload->>'facility_slug';
  v_date          date := (payload->>'time_entry_date')::date;
  v_np_pct        numeric := coalesce((payload->>'np_model_pct')::numeric, 12.6);
  v_snapshot_id   bigint;
  v_unit          jsonb;
  v_unit_id       bigint;
begin
  if v_facility_slug is null or v_date is null then
    raise exception 'push_daily_snapshot: facility_slug and time_entry_date are required';
  end if;

  select id into v_facility_id from facilities where slug = v_facility_slug and active;
  if v_facility_id is null then
    raise exception 'push_daily_snapshot: unknown facility slug %', v_facility_slug;
  end if;

  if not app.can_write_facility(v_facility_id) then
    raise exception 'push_daily_snapshot: not authorized for facility %', v_facility_slug;
  end if;

  insert into daily_snapshots (facility_id, time_entry_date, np_model_pct, created_by, updated_by)
  values (v_facility_id, v_date, v_np_pct, auth.uid(), auth.uid())
  on conflict (facility_id, time_entry_date) do update
    set np_model_pct = excluded.np_model_pct,
        updated_by   = auth.uid()
  returning id into v_snapshot_id;

  -- Replace unit rows wholesale — simpler than diffing.
  delete from unit_daily_census where snapshot_id = v_snapshot_id;

  for v_unit in select * from jsonb_array_elements(coalesce(payload->'units', '[]'::jsonb))
  loop
    select id into v_unit_id
    from units
    where facility_id = v_facility_id
      and (key = v_unit->>'key' or code = v_unit->>'code');

    if v_unit_id is null then
      raise exception 'push_daily_snapshot: unknown unit key/code in payload: %', v_unit;
    end if;

    insert into unit_daily_census
      (snapshot_id, unit_id, census, obs_hours, obs_notes, np_pct)
    values (
      v_snapshot_id,
      v_unit_id,
      coalesce((v_unit->>'census')::int, 0),
      coalesce((v_unit->>'obs_hours')::numeric, 0),
      coalesce(v_unit->>'obs_notes', ''),
      nullif(v_unit->>'np_pct','')::numeric
    );
  end loop;

  return v_snapshot_id;
end $$;

comment on function push_daily_snapshot(jsonb) is
  'Upsert one daily snapshot. Replaces the Power Automate webhook.';

-- ---------------------------------------------------------------------------
-- ingest_payroll — called by the Supabase Edge Function after parsing the
-- Workday Time Summary `.xlsx`. Creates a payroll_period and replaces the
-- per-unit and per-fixed-dept actual rows.
--
-- Payload shape:
--   {
--     facility_slug: 'highland',
--     start_date: '2026-05-03', end_date: '2026-05-03', day_count: 1,
--     file_name: 'TT_Time_Summary_050326.xlsx',
--     unit_actuals: [
--       { payroll_bu: 'Acute Adult-100E', hours: 118, reg_hours: 100, ot_hours: 0,
--         np_hours: 12, wages: 3460.02, headcount: 10, fte_sum: 8.5, jobs: {...} },
--       ...
--     ],
--     fixed_actuals: [
--       { name: 'Intake', hours: ..., ... },
--       ...
--     ]
--   }
-- Returns the payroll_period_id.
-- ---------------------------------------------------------------------------
create or replace function ingest_payroll(payload jsonb)
returns bigint
language plpgsql security invoker set search_path = public, app as $$
declare
  v_facility_id bigint;
  v_period_id   bigint;
  v_row         jsonb;
  v_unit_id     bigint;
  v_dept_id     bigint;
begin
  select id into v_facility_id from facilities where slug = payload->>'facility_slug' and active;
  if v_facility_id is null then
    raise exception 'ingest_payroll: unknown facility slug %', payload->>'facility_slug';
  end if;

  if not app.can_write_facility(v_facility_id) then
    raise exception 'ingest_payroll: not authorized for facility';
  end if;

  insert into payroll_periods
    (facility_id, start_date, end_date, day_count, file_name, row_count, raw_payload, created_by)
  values (
    v_facility_id,
    (payload->>'start_date')::date,
    (payload->>'end_date')::date,
    coalesce((payload->>'day_count')::int, 1),
    payload->>'file_name',
    coalesce((payload->>'row_count')::int, 0),
    payload,
    auth.uid()
  )
  returning id into v_period_id;

  for v_row in select * from jsonb_array_elements(coalesce(payload->'unit_actuals', '[]'::jsonb))
  loop
    select id into v_unit_id from units
    where facility_id = v_facility_id and payroll_bu = v_row->>'payroll_bu';

    if v_unit_id is null then
      -- Unknown BU: skip silently; Edge Function logs it.
      continue;
    end if;

    insert into payroll_unit_actuals
      (period_id, unit_id, hours, reg_hours, ot_hours, np_hours, wages, headcount, fte_sum, jobs)
    values (
      v_period_id, v_unit_id,
      coalesce((v_row->>'hours')::numeric, 0),
      coalesce((v_row->>'reg_hours')::numeric, 0),
      coalesce((v_row->>'ot_hours')::numeric, 0),
      coalesce((v_row->>'np_hours')::numeric, 0),
      coalesce((v_row->>'wages')::numeric, 0),
      coalesce((v_row->>'headcount')::int, 0),
      coalesce((v_row->>'fte_sum')::numeric, 0),
      coalesce(v_row->'jobs', '{}'::jsonb)
    );
  end loop;

  for v_row in select * from jsonb_array_elements(coalesce(payload->'fixed_actuals', '[]'::jsonb))
  loop
    -- Fixed depts can match by name or by alias entry.
    select id into v_dept_id from fixed_departments
    where facility_id = v_facility_id
      and (name = v_row->>'name' or (v_row->>'name') = any(payroll_aliases))
    limit 1;

    if v_dept_id is null then
      continue;
    end if;

    insert into payroll_fixed_actuals
      (period_id, fixed_dept_id, hours, reg_hours, ot_hours, np_hours, wages, headcount, fte_sum, jobs)
    values (
      v_period_id, v_dept_id,
      coalesce((v_row->>'hours')::numeric, 0),
      coalesce((v_row->>'reg_hours')::numeric, 0),
      coalesce((v_row->>'ot_hours')::numeric, 0),
      coalesce((v_row->>'np_hours')::numeric, 0),
      coalesce((v_row->>'wages')::numeric, 0),
      coalesce((v_row->>'headcount')::int, 0),
      coalesce((v_row->>'fte_sum')::numeric, 0),
      coalesce(v_row->'jobs', '{}'::jsonb)
    );
  end loop;

  return v_period_id;
end $$;

comment on function ingest_payroll(jsonb) is
  'Replace payroll actuals for a period. Called by the payroll Edge Function.';

commit;
