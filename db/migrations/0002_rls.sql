-- 0002_rls.sql — row-level security policies.
-- Predicates lean on three helper functions (defined first) so policies stay
-- short and consistent. Magic-link (D1) means every request carries a JWT
-- whose `sub` is the auth.users.id; we look that user up in app_users to
-- find their role and which facility_ids they may see/write.

begin;

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
create or replace function app.current_role() returns app.user_role
language sql stable security definer set search_path = '' as $$
  select role from public.app_users where id = auth.uid() and active
$$;

create or replace function app.is_system_admin() returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce(app.current_role() = 'system_admin', false)
$$;

create or replace function app.can_read_facility(fid bigint) returns boolean
language sql stable security definer set search_path = '' as $$
  select case
    when auth.uid() is null then false
    when app.is_system_admin() then true
    else exists (
      select 1 from public.app_users u
      where u.id = auth.uid() and u.active and fid = any(u.facility_ids)
    )
  end
$$;

create or replace function app.can_write_facility(fid bigint) returns boolean
language sql stable security definer set search_path = '' as $$
  select case
    when auth.uid() is null then false
    when app.is_system_admin() then true
    else exists (
      select 1 from public.app_users u
      where u.id = auth.uid() and u.active
        and fid = any(u.facility_ids)
        and u.role in ('facility_admin','unit_lead')
    )
  end
$$;

-- ---------------------------------------------------------------------------
-- Enable RLS on every table that carries facility-scoped data
-- ---------------------------------------------------------------------------
alter table facilities                enable row level security;
alter table app_users                 enable row level security;
alter table units                     enable row level security;
alter table fixed_departments         enable row level security;
alter table staffing_grids            enable row level security;
alter table daily_snapshots           enable row level security;
alter table unit_daily_census         enable row level security;
alter table payroll_periods           enable row level security;
alter table payroll_unit_actuals      enable row level security;
alter table payroll_fixed_actuals     enable row level security;
alter table mtd_periods               enable row level security;
alter table mtd_unit_actuals          enable row level security;
alter table mtd_fixed_actuals         enable row level security;
alter table daily_snapshot_history    enable row level security;

-- ---------------------------------------------------------------------------
-- facilities
-- ---------------------------------------------------------------------------
drop policy if exists facilities_select on facilities;
create policy facilities_select on facilities for select
  using (app.can_read_facility(id));

drop policy if exists facilities_admin_write on facilities;
create policy facilities_admin_write on facilities for all
  using (app.is_system_admin())
  with check (app.is_system_admin());

-- ---------------------------------------------------------------------------
-- app_users — users see themselves; system_admin sees all
-- ---------------------------------------------------------------------------
drop policy if exists app_users_self_select on app_users;
create policy app_users_self_select on app_users for select
  using (id = auth.uid() or app.is_system_admin());

drop policy if exists app_users_admin_write on app_users;
create policy app_users_admin_write on app_users for all
  using (app.is_system_admin())
  with check (app.is_system_admin());

-- ---------------------------------------------------------------------------
-- units, fixed_departments, staffing_grids — read by facility members,
-- write by facility_admin or system_admin
-- ---------------------------------------------------------------------------
drop policy if exists units_select on units;
create policy units_select on units for select
  using (app.can_read_facility(facility_id));

drop policy if exists units_write on units;
create policy units_write on units for all
  using (app.is_system_admin()
         or (app.can_write_facility(facility_id)
             and app.current_role() = 'facility_admin'))
  with check (app.is_system_admin()
              or (app.can_write_facility(facility_id)
                  and app.current_role() = 'facility_admin'));

drop policy if exists fixed_depts_select on fixed_departments;
create policy fixed_depts_select on fixed_departments for select
  using (app.can_read_facility(facility_id));

drop policy if exists fixed_depts_write on fixed_departments;
create policy fixed_depts_write on fixed_departments for all
  using (app.is_system_admin()
         or (app.can_write_facility(facility_id)
             and app.current_role() = 'facility_admin'))
  with check (app.is_system_admin()
              or (app.can_write_facility(facility_id)
                  and app.current_role() = 'facility_admin'));

drop policy if exists grids_select on staffing_grids;
create policy grids_select on staffing_grids for select
  using (app.can_read_facility(facility_id));

drop policy if exists grids_write on staffing_grids;
create policy grids_write on staffing_grids for all
  using (app.is_system_admin())
  with check (app.is_system_admin());

-- ---------------------------------------------------------------------------
-- daily_snapshots + unit_daily_census — read by facility members,
-- write by facility_admin or unit_lead
-- ---------------------------------------------------------------------------
drop policy if exists snapshots_select on daily_snapshots;
create policy snapshots_select on daily_snapshots for select
  using (app.can_read_facility(facility_id));

drop policy if exists snapshots_write on daily_snapshots;
create policy snapshots_write on daily_snapshots for all
  using (app.can_write_facility(facility_id))
  with check (app.can_write_facility(facility_id));

drop policy if exists unit_census_select on unit_daily_census;
create policy unit_census_select on unit_daily_census for select
  using (exists (
    select 1 from daily_snapshots s
    where s.id = unit_daily_census.snapshot_id
      and app.can_read_facility(s.facility_id)
  ));

drop policy if exists unit_census_write on unit_daily_census;
create policy unit_census_write on unit_daily_census for all
  using (exists (
    select 1 from daily_snapshots s
    where s.id = unit_daily_census.snapshot_id
      and app.can_write_facility(s.facility_id)
  ))
  with check (exists (
    select 1 from daily_snapshots s
    where s.id = unit_daily_census.snapshot_id
      and app.can_write_facility(s.facility_id)
  ));

-- ---------------------------------------------------------------------------
-- payroll + mtd
-- ---------------------------------------------------------------------------
drop policy if exists payroll_periods_select on payroll_periods;
create policy payroll_periods_select on payroll_periods for select
  using (app.can_read_facility(facility_id));

drop policy if exists payroll_periods_write on payroll_periods;
create policy payroll_periods_write on payroll_periods for all
  using (app.can_write_facility(facility_id))
  with check (app.can_write_facility(facility_id));

drop policy if exists payroll_unit_actuals_select on payroll_unit_actuals;
create policy payroll_unit_actuals_select on payroll_unit_actuals for select
  using (exists (
    select 1 from payroll_periods p
    where p.id = payroll_unit_actuals.period_id
      and app.can_read_facility(p.facility_id)
  ));

drop policy if exists payroll_unit_actuals_write on payroll_unit_actuals;
create policy payroll_unit_actuals_write on payroll_unit_actuals for all
  using (exists (
    select 1 from payroll_periods p
    where p.id = payroll_unit_actuals.period_id
      and app.can_write_facility(p.facility_id)
  ))
  with check (exists (
    select 1 from payroll_periods p
    where p.id = payroll_unit_actuals.period_id
      and app.can_write_facility(p.facility_id)
  ));

drop policy if exists payroll_fixed_actuals_select on payroll_fixed_actuals;
create policy payroll_fixed_actuals_select on payroll_fixed_actuals for select
  using (exists (
    select 1 from payroll_periods p
    where p.id = payroll_fixed_actuals.period_id
      and app.can_read_facility(p.facility_id)
  ));

drop policy if exists payroll_fixed_actuals_write on payroll_fixed_actuals;
create policy payroll_fixed_actuals_write on payroll_fixed_actuals for all
  using (exists (
    select 1 from payroll_periods p
    where p.id = payroll_fixed_actuals.period_id
      and app.can_write_facility(p.facility_id)
  ))
  with check (exists (
    select 1 from payroll_periods p
    where p.id = payroll_fixed_actuals.period_id
      and app.can_write_facility(p.facility_id)
  ));

drop policy if exists mtd_periods_select on mtd_periods;
create policy mtd_periods_select on mtd_periods for select
  using (app.can_read_facility(facility_id));

drop policy if exists mtd_periods_write on mtd_periods;
create policy mtd_periods_write on mtd_periods for all
  using (app.can_write_facility(facility_id))
  with check (app.can_write_facility(facility_id));

drop policy if exists mtd_unit_actuals_select on mtd_unit_actuals;
create policy mtd_unit_actuals_select on mtd_unit_actuals for select
  using (exists (
    select 1 from mtd_periods p
    where p.id = mtd_unit_actuals.mtd_period_id
      and app.can_read_facility(p.facility_id)
  ));

drop policy if exists mtd_unit_actuals_write on mtd_unit_actuals;
create policy mtd_unit_actuals_write on mtd_unit_actuals for all
  using (exists (
    select 1 from mtd_periods p
    where p.id = mtd_unit_actuals.mtd_period_id
      and app.can_write_facility(p.facility_id)
  ))
  with check (exists (
    select 1 from mtd_periods p
    where p.id = mtd_unit_actuals.mtd_period_id
      and app.can_write_facility(p.facility_id)
  ));

drop policy if exists mtd_fixed_actuals_select on mtd_fixed_actuals;
create policy mtd_fixed_actuals_select on mtd_fixed_actuals for select
  using (exists (
    select 1 from mtd_periods p
    where p.id = mtd_fixed_actuals.mtd_period_id
      and app.can_read_facility(p.facility_id)
  ));

drop policy if exists mtd_fixed_actuals_write on mtd_fixed_actuals;
create policy mtd_fixed_actuals_write on mtd_fixed_actuals for all
  using (exists (
    select 1 from mtd_periods p
    where p.id = mtd_fixed_actuals.mtd_period_id
      and app.can_write_facility(p.facility_id)
  ))
  with check (exists (
    select 1 from mtd_periods p
    where p.id = mtd_fixed_actuals.mtd_period_id
      and app.can_write_facility(p.facility_id)
  ));

-- ---------------------------------------------------------------------------
-- daily_snapshot_history — read-only to facility members
-- ---------------------------------------------------------------------------
drop policy if exists snapshot_history_select on daily_snapshot_history;
create policy snapshot_history_select on daily_snapshot_history for select
  using (app.can_read_facility(facility_id));

-- No insert/update/delete policy: only the trigger (security-definer) writes.

commit;
