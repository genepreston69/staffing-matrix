-- highland.sql — Highland Hospital seed.
-- Sources: index.html lines 1043-1108 (UNITS, ACUTE_GRID, DETOX_GRID,
-- FIXED_DEPTS, BASELINE_SALARY_FTE). Update these arrays when the prototype
-- changes upstream.

begin;

-- ---------------------------------------------------------------------------
-- Facility
-- ---------------------------------------------------------------------------
insert into facilities (slug, name, total_staffed_beds, fte_multiplier, default_np_pct, baseline_salary_fte)
values ('highland', 'Highland Hospital', 114, 1.40, 12.6, 33.625)
on conflict (slug) do update
  set name = excluded.name,
      total_staffed_beds = excluded.total_staffed_beds,
      fte_multiplier = excluded.fte_multiplier,
      default_np_pct = excluded.default_np_pct,
      baseline_salary_fte = excluded.baseline_salary_fte;

-- ---------------------------------------------------------------------------
-- Units
-- ---------------------------------------------------------------------------
with f as (select id from facilities where slug = 'highland')
insert into units (facility_id, code, key, payroll_bu, type, max_beds, label, sort_order)
select f.id, v.code, v.key, v.payroll_bu, v.type::app.unit_type, v.max_beds, v.label, v.ord
from f, (values
  ('u100e', '1East', 'Acute Adult-100E', 'acute', 18, '1 East · Child Acute',    1),
  ('u200e', '2East', 'Acute Child-200E', 'acute', 20, '2 East · Adult Acute',    2),
  ('u200w', '2West', 'Acute Adol-200W',  'acute', 20, '2 West · Adolescent',     3),
  ('u300e', '3East', 'Acute Adult-300E', 'acute', 20, '3 East · Adult Acute',    4),
  ('u300w', '3West', 'Acute Adult-300W', 'acute', 20, '3 West · Adult Acute',    5),
  ('detox', 'HRC',   'Acute Adult-100',  'detox', 16, 'HRC · SUD/Detox ASAM 3.7', 6)
) as v(code, key, payroll_bu, type, max_beds, label, ord)
on conflict (facility_id, code) do update
  set key = excluded.key,
      payroll_bu = excluded.payroll_bu,
      type = excluded.type,
      max_beds = excluded.max_beds,
      label = excluded.label,
      sort_order = excluded.sort_order;

-- ---------------------------------------------------------------------------
-- Fixed departments
-- ---------------------------------------------------------------------------
with f as (select id from facilities where slug = 'highland')
insert into fixed_departments (facility_id, name, category, headcount, baseline_fte, salary_fte, sort_order)
select f.id, v.name, v.category, v.hc, v.fte, v.salary_fte, v.ord
from f, (values
  ('Intake',                       'Clinical Operations', 19, 14.5, 0.000,  1),
  ('IP Clinical Administration',   'Clinical Operations',  9,  7.6, 3.000,  2),
  ('Case Management',              'Clinical Operations',  6,  5.6, 0.000,  3),
  ('Utilization Review',           'Clinical Operations',  4,  3.3, 3.000,  4),
  ('Recreation Therapy',           'Clinical Operations',  5,  2.9, 1.000,  5),
  ('IP Therapists',                'Clinical Operations', 12,  2.4, 4.000,  6),
  ('Medical Staff',                'Clinical Operations',  2,  0.1, 2.000,  7),
  ('Physicians',                   'Clinical Operations',  2,  0.2, 4.630,  8),
  ('Infection Control',            'Clinical Operations',  1,  0.2, 0.000,  9),
  ('Dietary',                      'Support Services',     8,  8.0, 2.000, 10),
  ('Housekeeping',                 'Support Services',     7,  6.0, 1.000, 11),
  ('Communications',               'Support Services',     3,  2.5, 0.000, 12),
  ('Plant Operations',             'Support Services',     4,  2.4, 1.000, 13),
  ('Medical Records',              'Support Services',     3,  2.1, 1.000, 14),
  ('Call Center',                  'Support Services',     1,  1.2, 0.000, 15),
  ('Marketing / Bus Dev',          'Admin / G&A',          2,  2.0, 2.000, 16),
  ('Administration',               'Admin / G&A',          3,  1.2, 2.000, 17),
  ('Facility Accounting',          'Admin / G&A',          2,  1.3, 2.000, 18),
  ('Facility QI/Risk Management',  'Admin / G&A',          3,  1.5, 1.000, 19),
  ('Facility HR',                  'Admin / G&A',          2,  0.1, 2.000, 20),
  ('Business Office',              'Admin / G&A',          1,  0.1, 0.000, 21),
  ('Facility IT',                  'Admin / G&A',          2,  0.1, 2.000, 22)
) as v(name, category, hc, fte, salary_fte, ord)
on conflict (facility_id, name) do update
  set category = excluded.category,
      headcount = excluded.headcount,
      baseline_fte = excluded.baseline_fte,
      salary_fte = excluded.salary_fte,
      sort_order = excluded.sort_order;

-- ---------------------------------------------------------------------------
-- Staffing grids — verbatim from index.html ACUTE_GRID + DETOX_GRID.
-- ACUTE censuses 1-20; DETOX censuses 1-16.
-- The arrays below are 1-indexed by census (i.e. index N → census N).
-- ---------------------------------------------------------------------------
with f as (select id as fid from facilities where slug = 'highland'),
acute(shift, rn_arr, lpn_arr, tech_arr) as (values
  ('day'::app.shift,
     array[1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1],
     array[0,0,0,0,0,0,0,0,0,0,0,0,0,1,1,1,1,1,1,1],
     array[1,1,1,1,1,1,1,1,1,1,1,2,2,1,1,1,2,2,2,2]),
  ('evening'::app.shift,
     array[1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1],
     array[0,0,0,0,0,0,0,0,0,0,0,0,0,1,1,1,1,1,1,1],
     array[1,1,1,1,1,1,1,1,1,1,1,2,2,1,1,1,2,2,2,2]),
  ('night'::app.shift,
     array[1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1],
     array[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
     array[1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,2,2,2,2,2])
)
insert into staffing_grids (facility_id, grid_type, census, shift, rn, lpn, tech)
select f.fid, 'acute'::app.unit_type, c.census, a.shift,
       a.rn_arr[c.census], a.lpn_arr[c.census], a.tech_arr[c.census]
from f, acute a, generate_series(1, 20) as c(census)
on conflict (facility_id, grid_type, census, shift) do update
  set rn = excluded.rn, lpn = excluded.lpn, tech = excluded.tech;

with f as (select id as fid from facilities where slug = 'highland'),
detox(shift) as (values
  ('day'::app.shift), ('evening'::app.shift), ('night'::app.shift)
)
insert into staffing_grids (facility_id, grid_type, census, shift, rn, lpn, tech)
select f.fid, 'detox'::app.unit_type, c.census, d.shift, 0, 1, 1
from f, detox d, generate_series(1, 16) as c(census)
on conflict (facility_id, grid_type, census, shift) do update
  set rn = excluded.rn, lpn = excluded.lpn, tech = excluded.tech;

commit;

-- Sanity check: row counts.
do $$ declare n_units int; n_grid int; n_fixed int;
begin
  select count(*) into n_units from units
   where facility_id = (select id from facilities where slug='highland');
  select count(*) into n_grid  from staffing_grids
   where facility_id = (select id from facilities where slug='highland');
  select count(*) into n_fixed from fixed_departments
   where facility_id = (select id from facilities where slug='highland');
  raise notice 'Highland seeded: % units, % fixed depts, % grid rows (expect 6, 22, 108)',
    n_units, n_fixed, n_grid;
  if n_units <> 6 or n_fixed <> 22 or n_grid <> 108 then
    raise exception 'Seed counts wrong.';
  end if;
end $$;
