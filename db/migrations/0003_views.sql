-- 0003_views.sql — formula reference implemented as views.
-- Section numbers reference DATA_DICTIONARY_AND_FORMULAS.md.
-- Naming: every view starts with v_; helper functions live in app schema.

begin;

-- ---------------------------------------------------------------------------
-- Helper: gross-up.    §2.2: prod / (1 - np%/100)
-- ---------------------------------------------------------------------------
create or replace function app.gross_up(prod numeric, np_pct numeric)
returns numeric language sql immutable as $$
  select case
    when np_pct is null or np_pct >= 100 then prod
    else prod / (1 - np_pct / 100)
  end
$$;

-- ---------------------------------------------------------------------------
-- Helper: clamp census to [0, max_beds].   §2.4
-- ---------------------------------------------------------------------------
create or replace function app.clamp_census(c integer, max_beds integer)
returns integer language sql immutable as $$
  select greatest(0, least(coalesce(c,0), max_beds))
$$;

-- ---------------------------------------------------------------------------
-- Helper: lookup grid row for a (facility, type, census, shift).
-- Implements §2.3 (index = census, capped at max-defined census;
-- census of 0 returns zeros).
-- ---------------------------------------------------------------------------
create or replace function app.grid_lookup(
  p_facility_id bigint,
  p_type        app.unit_type,
  p_census      integer,
  p_shift       app.shift
) returns table(rn integer, lpn integer, tech integer)
language sql stable as $$
  select
    case when p_census <= 0 then 0 else g.rn end,
    case when p_census <= 0 then 0 else g.lpn end,
    case when p_census <= 0 then 0 else g.tech end
  from staffing_grids g
  where g.facility_id = p_facility_id
    and g.grid_type   = p_type
    and g.shift       = p_shift
    and g.census      = least(
      greatest(p_census, 1),
      (select max(census) from staffing_grids
        where facility_id = p_facility_id and grid_type = p_type and shift = p_shift)
    )
  limit 1
$$;

-- ---------------------------------------------------------------------------
-- v_unit_staffing — for every unit_daily_census row, expand to per-shift
-- staffing positions using the grid. Implements §1.3, §1.4, §2.3, §2.4.
-- ---------------------------------------------------------------------------
create or replace view v_unit_staffing as
with shifts as (
  select unnest(array['day','evening','night']::app.shift[]) as shift
),
clamped as (
  select
    udc.id            as unit_daily_id,
    udc.snapshot_id,
    udc.unit_id,
    u.facility_id,
    u.type            as unit_type,
    u.key             as unit_key,
    u.payroll_bu,
    u.max_beds,
    udc.obs_hours,
    udc.obs_notes,
    coalesce(udc.np_pct, s.np_model_pct) as np_pct,
    app.clamp_census(udc.census, u.max_beds) as census,
    s.facility_id     as snapshot_facility_id,
    s.time_entry_date
  from unit_daily_census udc
  join units u            on u.id = udc.unit_id
  join daily_snapshots s  on s.id = udc.snapshot_id
)
select
  c.unit_daily_id,
  c.snapshot_id,
  c.unit_id,
  c.facility_id,
  c.time_entry_date,
  c.unit_key,
  c.payroll_bu,
  c.unit_type,
  c.census,
  c.max_beds,
  c.obs_hours,
  c.obs_notes,
  c.np_pct,
  sh.shift,
  g.rn,
  g.lpn,
  g.tech,
  (g.rn + g.lpn + g.tech) as shift_total,
  -- §2.5 unit occupancy
  round(c.census::numeric / c.max_beds * 100)::numeric(5,1) as unit_occupancy_pct,
  -- §2.15 patient:staff ratio per shift
  case when (g.rn + g.lpn + g.tech) > 0
       then round(c.census::numeric / (g.rn + g.lpn + g.tech), 1)
       else null end as patient_staff_ratio
from clamped c
cross join shifts sh
cross join lateral app.grid_lookup(c.facility_id, c.unit_type, c.census, sh.shift) g;

-- ---------------------------------------------------------------------------
-- v_snapshot_unit_totals — collapses three shifts back to one row per unit.
-- Used by the model-vs-actual variance view and the daily metrics rollup.
-- §2.19 model_daily_hours = total_positions * 8
-- ---------------------------------------------------------------------------
create or replace view v_snapshot_unit_totals as
select
  unit_daily_id,
  snapshot_id,
  unit_id,
  facility_id,
  time_entry_date,
  unit_key,
  payroll_bu,
  unit_type,
  census,
  max_beds,
  obs_hours,
  np_pct,
  unit_occupancy_pct,
  sum(rn)::int          as total_rn_positions,
  sum(lpn)::int         as total_lpn_positions,
  sum(tech)::int        as total_tech_positions,
  sum(shift_total)::int as total_shift_positions,
  sum(shift_total)::int * 8 as model_daily_hours
from v_unit_staffing
group by unit_daily_id, snapshot_id, unit_id, facility_id, time_entry_date,
         unit_key, payroll_bu, unit_type, census, max_beds, obs_hours, np_pct,
         unit_occupancy_pct;

-- ---------------------------------------------------------------------------
-- v_daily_metrics — facility-level rollup per snapshot.
-- Implements §2.6–§2.14: total positions, float, FTE, EPOB.
-- ---------------------------------------------------------------------------
create or replace view v_daily_metrics as
with totals as (
  select
    s.id              as snapshot_id,
    s.facility_id,
    s.time_entry_date,
    s.np_model_pct,
    s.payroll_period_id,
    s.fixed_source,
    f.fte_multiplier,
    f.total_staffed_beds,
    sum(t.census)                          as total_census,
    sum(t.obs_hours)                       as total_obs_hours,
    sum(t.total_rn_positions)              as total_rn,
    sum(t.total_lpn_positions)             as total_lpn,
    sum(t.total_tech_positions)            as total_tech,
    sum(t.total_shift_positions)           as total_shift_staff,
    -- §2.7 float: ceil(open acute units / 2)
    ceil(
      sum(case when t.unit_type = 'acute' and t.census > 0 then 1 else 0 end)::numeric / 2
    )::int                                 as float_shift_positions
  from daily_snapshots s
  join facilities f                on f.id = s.facility_id
  left join v_snapshot_unit_totals t on t.snapshot_id = s.id
  group by s.id, s.facility_id, s.time_entry_date, s.np_model_pct,
           s.payroll_period_id, s.fixed_source, f.fte_multiplier, f.total_staffed_beds
)
select
  snapshot_id,
  facility_id,
  time_entry_date,
  np_model_pct,
  payroll_period_id,
  fixed_source,
  total_census,
  total_staffed_beds,
  -- §2.5 facility occupancy
  case when total_staffed_beds > 0
       then round(total_census::numeric / total_staffed_beds * 100, 1)
       else 0 end                                              as occupancy_pct,
  total_rn,
  total_lpn,
  total_tech,
  total_shift_staff,
  float_shift_positions,
  -- §2.9 role-level FTE
  round(total_rn   * fte_multiplier, 1)                        as rn_prod_fte,
  round(total_lpn  * fte_multiplier, 1)                        as lpn_prod_fte,
  round(total_tech * fte_multiplier, 1)                        as tech_prod_fte,
  round(app.gross_up(total_rn   * fte_multiplier, np_model_pct), 1) as rn_adj_fte,
  round(app.gross_up(total_lpn  * fte_multiplier, np_model_pct), 1) as lpn_adj_fte,
  round(app.gross_up(total_tech * fte_multiplier, np_model_pct), 1) as tech_adj_fte,
  -- §2.7
  round(float_shift_positions * fte_multiplier, 1)             as float_prod_fte,
  round(app.gross_up(float_shift_positions * fte_multiplier, np_model_pct), 1) as float_adj_fte,
  -- §2.8 nursing prod FTE
  round(total_shift_staff * fte_multiplier, 1)                 as nursing_prod_fte,
  -- §2.10 1:1 observation
  round(total_obs_hours * 7.0 / 40.0, 1)                       as oneone_prod_fte,
  round(app.gross_up(total_obs_hours * 7.0 / 40.0, np_model_pct), 1) as oneone_adj_fte,
  -- §2.11 total variable
  round(
    total_shift_staff * fte_multiplier
    + float_shift_positions * fte_multiplier
    + total_obs_hours * 7.0 / 40.0
  , 1)                                                         as var_prod_fte,
  round(
    app.gross_up(
      total_shift_staff * fte_multiplier + float_shift_positions * fte_multiplier
    , np_model_pct)
    + app.gross_up(total_obs_hours * 7.0 / 40.0, np_model_pct)
  , 1)                                                         as var_adj_fte
from totals;

-- ---------------------------------------------------------------------------
-- v_facility_fixed — per-facility fixed FTE from the active source.
-- Falls back to baseline when no payroll period is linked.
-- ---------------------------------------------------------------------------
create or replace view v_facility_fixed as
with baseline as (
  select facility_id,
         sum(baseline_fte) as fixed_fte_baseline,
         sum(headcount)    as fixed_hc_baseline
  from fixed_departments
  where active
  group by facility_id
)
select b.facility_id, b.fixed_fte_baseline, b.fixed_hc_baseline
from baseline b;

-- ---------------------------------------------------------------------------
-- v_grand_metrics — variable + fixed roll-up + EPOB. Implements §2.13, §2.14.
-- ---------------------------------------------------------------------------
create or replace view v_grand_metrics as
select
  m.snapshot_id,
  m.facility_id,
  m.time_entry_date,
  m.total_census,
  m.var_prod_fte,
  m.var_adj_fte,
  f.fixed_fte_baseline                                  as fixed_fte,
  f.fixed_hc_baseline                                   as fixed_hc,
  round(m.var_prod_fte + f.fixed_fte_baseline, 1)       as grand_prod_fte,
  round(m.var_adj_fte  + f.fixed_fte_baseline, 1)       as grand_adj_fte,
  -- §2.14 EPOB (returns null when census is 0)
  case when m.total_census > 0
       then round(m.var_adj_fte / m.total_census, 2) end  as epob_direct_care,
  case when m.total_census > 0
       then round((m.var_adj_fte + f.fixed_fte_baseline) / m.total_census, 2) end as epob_total_facility
from v_daily_metrics m
left join v_facility_fixed f on f.facility_id = m.facility_id;

-- ---------------------------------------------------------------------------
-- v_unit_variance — payroll vs model per (period, unit). §2.20–§2.23
-- ---------------------------------------------------------------------------
create or replace view v_unit_variance as
select
  pua.period_id,
  pp.facility_id,
  pp.start_date,
  pp.end_date,
  pp.day_count,
  u.id            as unit_id,
  u.key           as unit_key,
  u.payroll_bu,
  pua.hours       as actual_hours,
  pua.np_hours    as actual_np_hours,
  pua.ot_hours    as actual_ot_hours,
  pua.headcount   as actual_headcount,
  pua.wages       as actual_wages,
  -- §2.20 actual daily hours
  round(pua.hours / pp.day_count, 1)                                   as actual_hrs_day,
  -- §2.18 actual NP%
  case when pua.hours > 0
       then round(pua.np_hours / pua.hours * 100, 1) end               as actual_np_pct,
  -- §2.22 actual variable FTE (productive only)
  round(((pua.hours - pua.np_hours) / pp.day_count) * 7 / 40, 1)       as actual_var_fte
from payroll_unit_actuals pua
join payroll_periods pp on pp.id = pua.period_id
join units u            on u.id = pua.unit_id;

commit;
