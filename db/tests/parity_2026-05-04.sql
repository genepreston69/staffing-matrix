-- parity_2026-05-04.sql
-- Verifies that v_daily_metrics + v_grand_metrics reproduce the prototype's
-- output for Highland on 2026-05-04. Source-of-truth: data/shared_staffing.json.
--
-- Inputs (from shared_staffing.json):
--   Census:    1East=16, 2East=17, 2West=20, 3East=15, 3West=16, HRC=4
--   Obs hours: 1East=25, all others 0
--   NP model%: 12.6
--
-- Expected variable-side outputs (from shared_staffing.json, all
-- deterministic given inputs + grids):
--   TotalCensus       88
--   Occupancy%        77.2
--   Total_RN          15      LPN  13     Tech 26     ShiftStaff 54
--   FloatShiftPos     3
--   RN_ProdFTE        21.0    AdjFTE 24.0
--   LPN_ProdFTE       18.2    AdjFTE 20.8
--   Tech_ProdFTE      36.4    AdjFTE 41.6
--   Float_ProdFTE     4.2     AdjFTE 4.8
--   OneOne_ProdFTE    4.4     AdjFTE 5.0   (25 * 7 / 40 = 4.375)
--   VarProdFTE        84.2    VarAdjFTE 96.3
--
-- Run with: psql -v ON_ERROR_STOP=1 -f db/tests/parity_2026-05-04.sql

begin;
-- Tests run as superuser/postgres so RLS doesn't get in the way.
set local row_security = off;

-- Clean any prior test snapshot for the same date (idempotent re-runs).
delete from daily_snapshots
 where facility_id = (select id from facilities where slug = 'highland')
   and time_entry_date = '2026-05-04';

-- Seed snapshot + unit_daily_census rows directly (bypassing RPC so the test
-- exercises the views, not the RPC's auth path).
with f as (select id as fid from facilities where slug='highland'),
ins as (
  insert into daily_snapshots (facility_id, time_entry_date, np_model_pct, fixed_source)
  select f.fid, '2026-05-04', 12.6, 'baseline' from f
  returning id as snapshot_id, facility_id
)
insert into unit_daily_census (snapshot_id, unit_id, census, obs_hours, obs_notes, np_pct)
select ins.snapshot_id,
       u.id,
       v.census,
       v.obs_hours,
       '',
       null
from ins
join units u on u.facility_id = ins.facility_id
join (values
  ('1East', 16, 25),
  ('2East', 17,  0),
  ('2West', 20,  0),
  ('3East', 15,  0),
  ('3West', 16,  0),
  ('HRC',    4,  0)
) as v(key, census, obs_hours) on v.key = u.key;

-- ---------------------------------------------------------------------------
-- Assertion helper
-- ---------------------------------------------------------------------------
create or replace function pg_temp.assert_eq(label text, actual numeric, expected numeric, tol numeric default 0.05)
returns void language plpgsql as $$
begin
  if actual is null then
    raise exception 'PARITY FAIL [%] expected %, got NULL', label, expected;
  end if;
  if abs(actual - expected) > tol then
    raise exception 'PARITY FAIL [%] expected %, got % (tol %)',
      label, expected, actual, tol;
  end if;
  raise notice 'PARITY OK   [%] = %', label, actual;
end $$;

-- ---------------------------------------------------------------------------
-- Pull metrics for the snapshot we just inserted
-- ---------------------------------------------------------------------------
do $$
declare
  m record;
  g record;
  fixed_baseline numeric;
begin
  select * into m from v_daily_metrics
   where facility_id = (select id from facilities where slug='highland')
     and time_entry_date = '2026-05-04';

  select * into g from v_grand_metrics
   where facility_id = (select id from facilities where slug='highland')
     and time_entry_date = '2026-05-04';

  -- Per-unit shift totals are an additional sanity check (against
  -- shared_staffing.json *_ShiftTotal fields: 9, 11, 11, 8, 9, 6).
  perform pg_temp.assert_eq('1East shift total',
    (select total_shift_positions from v_snapshot_unit_totals
       join units u on u.id = v_snapshot_unit_totals.unit_id
      where snapshot_id = m.snapshot_id and u.key='1East'), 9);
  perform pg_temp.assert_eq('2East shift total',
    (select total_shift_positions from v_snapshot_unit_totals
       join units u on u.id = v_snapshot_unit_totals.unit_id
      where snapshot_id = m.snapshot_id and u.key='2East'), 11);
  perform pg_temp.assert_eq('2West shift total',
    (select total_shift_positions from v_snapshot_unit_totals
       join units u on u.id = v_snapshot_unit_totals.unit_id
      where snapshot_id = m.snapshot_id and u.key='2West'), 11);
  perform pg_temp.assert_eq('3East shift total',
    (select total_shift_positions from v_snapshot_unit_totals
       join units u on u.id = v_snapshot_unit_totals.unit_id
      where snapshot_id = m.snapshot_id and u.key='3East'), 8);
  perform pg_temp.assert_eq('3West shift total',
    (select total_shift_positions from v_snapshot_unit_totals
       join units u on u.id = v_snapshot_unit_totals.unit_id
      where snapshot_id = m.snapshot_id and u.key='3West'), 9);
  perform pg_temp.assert_eq('HRC shift total',
    (select total_shift_positions from v_snapshot_unit_totals
       join units u on u.id = v_snapshot_unit_totals.unit_id
      where snapshot_id = m.snapshot_id and u.key='HRC'), 6);

  -- Facility rollups
  perform pg_temp.assert_eq('total_census',         m.total_census,        88);
  perform pg_temp.assert_eq('occupancy_pct',        m.occupancy_pct,       77.2, 0.1);
  perform pg_temp.assert_eq('total_rn',             m.total_rn,            15);
  perform pg_temp.assert_eq('total_lpn',            m.total_lpn,           13);
  perform pg_temp.assert_eq('total_tech',           m.total_tech,          26);
  perform pg_temp.assert_eq('total_shift_staff',    m.total_shift_staff,   54);
  perform pg_temp.assert_eq('float_shift_positions',m.float_shift_positions, 3);

  perform pg_temp.assert_eq('rn_prod_fte',          m.rn_prod_fte,         21.0);
  perform pg_temp.assert_eq('rn_adj_fte',           m.rn_adj_fte,          24.0, 0.1);
  perform pg_temp.assert_eq('lpn_prod_fte',         m.lpn_prod_fte,        18.2);
  perform pg_temp.assert_eq('lpn_adj_fte',          m.lpn_adj_fte,         20.8, 0.1);
  perform pg_temp.assert_eq('tech_prod_fte',        m.tech_prod_fte,       36.4);
  perform pg_temp.assert_eq('tech_adj_fte',         m.tech_adj_fte,        41.6, 0.1);
  perform pg_temp.assert_eq('float_prod_fte',       m.float_prod_fte,      4.2);
  perform pg_temp.assert_eq('float_adj_fte',        m.float_adj_fte,       4.8, 0.1);
  perform pg_temp.assert_eq('oneone_prod_fte',      m.oneone_prod_fte,     4.4, 0.1);
  perform pg_temp.assert_eq('oneone_adj_fte',       m.oneone_adj_fte,      5.0, 0.1);
  perform pg_temp.assert_eq('var_prod_fte',         m.var_prod_fte,        84.2, 0.1);
  perform pg_temp.assert_eq('var_adj_fte',          m.var_adj_fte,         96.3, 0.1);

  -- Grand metrics with baseline fixed (Highland baseline FTE = 65.3 per seed).
  select sum(baseline_fte) into fixed_baseline
    from fixed_departments
   where facility_id = (select id from facilities where slug='highland')
     and active;

  perform pg_temp.assert_eq('fixed_fte_baseline',   g.fixed_fte,           fixed_baseline, 0.01);
  perform pg_temp.assert_eq('grand_prod_fte',       g.grand_prod_fte,
    round((m.var_prod_fte + fixed_baseline)::numeric, 1), 0.1);
  perform pg_temp.assert_eq('grand_adj_fte',        g.grand_adj_fte,
    round((m.var_adj_fte + fixed_baseline)::numeric, 1), 0.1);
  perform pg_temp.assert_eq('epob_direct_care',     g.epob_direct_care,
    round((m.var_adj_fte / 88)::numeric, 2), 0.01);

  raise notice '------------------------------------------------------------------';
  raise notice 'PARITY 2026-05-04 — all assertions passed.';
  raise notice '  Variable: prod=% adj=%   Grand prod=% adj=%   DC EPOB=%',
    m.var_prod_fte, m.var_adj_fte, g.grand_prod_fte, g.grand_adj_fte, g.epob_direct_care;
end $$;

rollback;  -- don't pollute the database with the test snapshot
