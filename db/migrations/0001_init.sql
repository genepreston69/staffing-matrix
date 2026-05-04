-- 0001_init.sql — core schema for the staffing matrix rewrite.
-- See docs/supabase-migration-plan.md §3 for the data-model overview.
-- Idempotent for dev: each statement uses IF NOT EXISTS where Postgres allows it.

begin;

-- ---------------------------------------------------------------------------
-- Extensions & helper schema
-- ---------------------------------------------------------------------------
create extension if not exists "pgcrypto";
create schema if not exists app;       -- helper fns + types live here
comment on schema app is 'Application helpers (RLS predicates, enums, RPCs).';

-- ---------------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------------
do $$ begin
  create type app.user_role as enum ('system_admin','facility_admin','unit_lead','viewer');
exception when duplicate_object then null; end $$;

do $$ begin
  create type app.unit_type as enum ('acute','detox');
exception when duplicate_object then null; end $$;

do $$ begin
  create type app.shift as enum ('day','evening','night');
exception when duplicate_object then null; end $$;

do $$ begin
  create type app.fixed_source as enum ('baseline','payroll','mtd');
exception when duplicate_object then null; end $$;

-- ---------------------------------------------------------------------------
-- Reusable updated_at trigger
-- ---------------------------------------------------------------------------
create or replace function app.set_updated_at() returns trigger
language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

-- ---------------------------------------------------------------------------
-- facilities
-- ---------------------------------------------------------------------------
create table if not exists facilities (
  id                  bigint generated always as identity primary key,
  slug                text not null unique,
  name                text not null,
  total_staffed_beds  integer not null check (total_staffed_beds > 0),
  fte_multiplier      numeric(4,2) not null default 1.40 check (fte_multiplier > 0),
  default_np_pct      numeric(5,2) not null default 12.6 check (default_np_pct between 0 and 40),
  baseline_salary_fte numeric(8,3) not null default 0,
  active              boolean not null default true,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);

drop trigger if exists trg_facilities_updated_at on facilities;
create trigger trg_facilities_updated_at before update on facilities
  for each row execute function app.set_updated_at();

-- ---------------------------------------------------------------------------
-- app_users — profile mirror of auth.users (magic-link)
-- ---------------------------------------------------------------------------
create table if not exists app_users (
  id            uuid primary key references auth.users(id) on delete cascade,
  email         text not null unique,
  full_name     text,
  role          app.user_role not null default 'viewer',
  facility_ids  bigint[] not null default '{}',     -- empty = none, system_admin ignores
  unit_ids      bigint[] not null default '{}',     -- only meaningful for unit_lead
  active        boolean not null default true,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

drop trigger if exists trg_app_users_updated_at on app_users;
create trigger trg_app_users_updated_at before update on app_users
  for each row execute function app.set_updated_at();

-- ---------------------------------------------------------------------------
-- units
-- ---------------------------------------------------------------------------
create table if not exists units (
  id            bigint generated always as identity primary key,
  facility_id   bigint not null references facilities(id) on delete cascade,
  code          text not null,                    -- e.g. 'u100e' — stable internal id
  key           text not null,                    -- e.g. '1East' — used in payload field names
  payroll_bu    text not null,                    -- matches Workday "Acute Adult-100E"
  type          app.unit_type not null,
  max_beds      integer not null check (max_beds > 0),
  label         text not null,
  sort_order    integer not null default 0,
  active        boolean not null default true,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  unique (facility_id, code),
  unique (facility_id, key),
  unique (facility_id, payroll_bu)
);

drop trigger if exists trg_units_updated_at on units;
create trigger trg_units_updated_at before update on units
  for each row execute function app.set_updated_at();

-- ---------------------------------------------------------------------------
-- fixed_departments
-- ---------------------------------------------------------------------------
create table if not exists fixed_departments (
  id            bigint generated always as identity primary key,
  facility_id   bigint not null references facilities(id) on delete cascade,
  name          text not null,
  category      text not null,                    -- 'Clinical Operations' | 'Support Services' | 'Admin / G&A'
  headcount     integer not null default 0,
  baseline_fte  numeric(6,2) not null default 0,
  salary_fte    numeric(6,3) not null default 0,
  -- Map alternate payroll BU names that should fold into this row
  payroll_aliases text[] not null default '{}',
  sort_order    integer not null default 0,
  active        boolean not null default true,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  unique (facility_id, name)
);

drop trigger if exists trg_fixed_departments_updated_at on fixed_departments;
create trigger trg_fixed_departments_updated_at before update on fixed_departments
  for each row execute function app.set_updated_at();

-- ---------------------------------------------------------------------------
-- staffing_grids — per-facility, per-type, per-shift, per-census
-- Each row says: "for this grid_type at this census level on this shift,
-- the model calls for these RN/LPN/Tech counts." Implements §1.3, §1.4.
-- ---------------------------------------------------------------------------
create table if not exists staffing_grids (
  facility_id   bigint not null references facilities(id) on delete cascade,
  grid_type     app.unit_type not null,
  census        integer not null check (census >= 1),
  shift         app.shift not null,
  rn            integer not null default 0 check (rn >= 0),
  lpn           integer not null default 0 check (lpn >= 0),
  tech          integer not null default 0 check (tech >= 0),
  primary key (facility_id, grid_type, census, shift)
);

-- ---------------------------------------------------------------------------
-- daily_snapshots — one row per (facility_id, time_entry_date).
-- The "model" inputs; staffing positions and FTE are derived in views.
-- ---------------------------------------------------------------------------
create table if not exists daily_snapshots (
  id              bigint generated always as identity primary key,
  facility_id     bigint not null references facilities(id) on delete cascade,
  time_entry_date date not null,
  np_model_pct    numeric(5,2) not null default 12.6 check (np_model_pct between 0 and 40),
  payroll_period_id bigint,                       -- nullable FK; set after payroll arrives
  fixed_source    app.fixed_source not null default 'baseline',
  notes           text,
  created_by      uuid references auth.users(id) on delete set null,
  updated_by      uuid references auth.users(id) on delete set null,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  unique (facility_id, time_entry_date)
);

drop trigger if exists trg_daily_snapshots_updated_at on daily_snapshots;
create trigger trg_daily_snapshots_updated_at before update on daily_snapshots
  for each row execute function app.set_updated_at();

-- ---------------------------------------------------------------------------
-- unit_daily_census — per-unit inputs for a snapshot
-- ---------------------------------------------------------------------------
create table if not exists unit_daily_census (
  id            bigint generated always as identity primary key,
  snapshot_id   bigint not null references daily_snapshots(id) on delete cascade,
  unit_id       bigint not null references units(id) on delete restrict,
  census        integer not null check (census >= 0),
  obs_hours     numeric(6,2) not null default 0 check (obs_hours >= 0),
  obs_notes     text not null default '',
  np_pct        numeric(5,2),                     -- nullable; falls back to snapshot.np_model_pct
  unique (snapshot_id, unit_id)
);

-- ---------------------------------------------------------------------------
-- payroll_periods — one per uploaded Workday file
-- ---------------------------------------------------------------------------
create table if not exists payroll_periods (
  id                bigint generated always as identity primary key,
  facility_id       bigint not null references facilities(id) on delete cascade,
  start_date        date not null,
  end_date          date not null,
  day_count         integer not null check (day_count >= 1),
  file_name         text,
  row_count         integer,
  raw_payload       jsonb,                        -- kept for replay / audit
  created_by        uuid references auth.users(id) on delete set null,
  created_at        timestamptz not null default now(),
  check (end_date >= start_date)
);

alter table daily_snapshots
  drop constraint if exists daily_snapshots_payroll_period_id_fkey;
alter table daily_snapshots
  add constraint daily_snapshots_payroll_period_id_fkey
  foreign key (payroll_period_id) references payroll_periods(id) on delete set null;

-- ---------------------------------------------------------------------------
-- payroll_unit_actuals — variable side
-- ---------------------------------------------------------------------------
create table if not exists payroll_unit_actuals (
  id            bigint generated always as identity primary key,
  period_id     bigint not null references payroll_periods(id) on delete cascade,
  unit_id       bigint not null references units(id) on delete restrict,
  hours         numeric(10,2) not null default 0,
  reg_hours     numeric(10,2) not null default 0,
  ot_hours      numeric(10,2) not null default 0,
  np_hours      numeric(10,2) not null default 0,
  wages         numeric(12,2) not null default 0,
  headcount     integer not null default 0,
  fte_sum       numeric(8,3) not null default 0,
  jobs          jsonb not null default '{}'::jsonb,
  unique (period_id, unit_id)
);

-- ---------------------------------------------------------------------------
-- payroll_fixed_actuals — fixed-department side
-- ---------------------------------------------------------------------------
create table if not exists payroll_fixed_actuals (
  id              bigint generated always as identity primary key,
  period_id       bigint not null references payroll_periods(id) on delete cascade,
  fixed_dept_id   bigint not null references fixed_departments(id) on delete restrict,
  hours           numeric(10,2) not null default 0,
  reg_hours       numeric(10,2) not null default 0,
  ot_hours        numeric(10,2) not null default 0,
  np_hours        numeric(10,2) not null default 0,
  wages           numeric(12,2) not null default 0,
  headcount       integer not null default 0,
  fte_sum         numeric(8,3) not null default 0,
  jobs            jsonb not null default '{}'::jsonb,
  unique (period_id, fixed_dept_id)
);

-- ---------------------------------------------------------------------------
-- mtd_periods + actuals — supports the EPOB & Labor Mgmt page
-- ---------------------------------------------------------------------------
create table if not exists mtd_periods (
  id            bigint generated always as identity primary key,
  facility_id   bigint not null references facilities(id) on delete cascade,
  start_date    date not null,
  end_date      date not null,
  file_name     text,
  notes         text,
  created_by    uuid references auth.users(id) on delete set null,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  check (end_date >= start_date),
  unique (facility_id, start_date, end_date)
);

drop trigger if exists trg_mtd_periods_updated_at on mtd_periods;
create trigger trg_mtd_periods_updated_at before update on mtd_periods
  for each row execute function app.set_updated_at();

create table if not exists mtd_unit_actuals (
  id              bigint generated always as identity primary key,
  mtd_period_id   bigint not null references mtd_periods(id) on delete cascade,
  unit_id         bigint not null references units(id) on delete restrict,
  hours           numeric(10,2) not null default 0,
  np_hours        numeric(10,2) not null default 0,
  ot_hours        numeric(10,2) not null default 0,
  wages           numeric(12,2) not null default 0,
  headcount       integer not null default 0,
  budget_fte      numeric(8,3),
  unique (mtd_period_id, unit_id)
);

create table if not exists mtd_fixed_actuals (
  id              bigint generated always as identity primary key,
  mtd_period_id   bigint not null references mtd_periods(id) on delete cascade,
  fixed_dept_id   bigint not null references fixed_departments(id) on delete restrict,
  hours           numeric(10,2) not null default 0,
  np_hours        numeric(10,2) not null default 0,
  wages           numeric(12,2) not null default 0,
  headcount       integer not null default 0,
  budget_fte      numeric(8,3),
  unique (mtd_period_id, fixed_dept_id)
);

-- ---------------------------------------------------------------------------
-- daily_snapshot_history — audit trail (D6)
-- ---------------------------------------------------------------------------
create table if not exists daily_snapshot_history (
  id            bigint generated always as identity primary key,
  snapshot_id   bigint not null,                  -- not FK: survives snapshot deletion
  facility_id   bigint not null,
  time_entry_date date not null,
  snapshot_data jsonb not null,                   -- full snapshot + unit_daily_census rows
  changed_by    uuid,
  changed_at    timestamptz not null default now()
);

create index if not exists ix_dsh_facility_date
  on daily_snapshot_history (facility_id, time_entry_date);

-- ---------------------------------------------------------------------------
-- Helpful indexes
-- ---------------------------------------------------------------------------
create index if not exists ix_units_facility on units (facility_id) where active;
create index if not exists ix_fixed_depts_facility on fixed_departments (facility_id) where active;
create index if not exists ix_daily_snapshots_facility_date on daily_snapshots (facility_id, time_entry_date desc);
create index if not exists ix_unit_census_snapshot on unit_daily_census (snapshot_id);
create index if not exists ix_payroll_periods_facility on payroll_periods (facility_id, start_date desc);
create index if not exists ix_payroll_unit_actuals_period on payroll_unit_actuals (period_id);
create index if not exists ix_payroll_fixed_actuals_period on payroll_fixed_actuals (period_id);
create index if not exists ix_mtd_periods_facility on mtd_periods (facility_id, start_date desc);

commit;
