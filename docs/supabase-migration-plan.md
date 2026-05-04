# Staffing Matrix — Backend & Rewrite Plan

Migration of the prototype (`index.html`, `epob_labor_management.html`) onto a
Supabase backend with a React + Tailwind frontend, scaling from a single
facility (Highland Hospital) to multiple facilities across the organization.

This plan answers four questions: **what we're building**, **in what order**,
**what decisions need to be made before code is written**, and **how we get
there without breaking the live tool the operations team already depends on**.

---

## 1. Goals & non-goals

**Goals**
- Replace SharePoint + Power Automate as the system of record with Postgres
  (Supabase). Every field currently pushed to the SharePoint list lands in
  typed, normalized tables.
- Multi-facility from day one (rows are scoped by `facility_id`), even if only
  Highland is loaded initially.
- Auth + row-level security so a 3 East charge nurse only sees/edits 3 East,
  a facility admin sees the whole facility, a system admin sees everything.
- Rebuild the UI in **React + Tailwind + Vite**, page-by-page, deployed on
  Vercel or Netlify. Keep the prototype HTML reachable until each page reaches
  parity.
- Move the **calculations** (see `DATA_DICTIONARY_AND_FORMULAS.md` §2.1–2.23)
  into Postgres views and RPC functions so any downstream tool — Power BI, the
  React app, exports — sees the same numbers.

**Non-goals (for this rewrite)**
- Replacing Workday / payroll source systems. Excel upload of the time summary
  stays as the ingestion entry point.
- Replacing Power BI dashboards. They keep working; we just point them at
  Supabase instead of SharePoint.
- Mobile-native app. The React app should be responsive, but no React Native.
- Real-time multi-user editing of the same census row (single-writer per
  unit/day is fine; we'll use `updated_at` + last-write-wins).

---

## 2. Decisions that must be made before any schema or code

These shape the whole design. **Don't start the schema (a) until each is
answered.** Defaults are recommendations; flag any you want to change.

| # | Decision | Recommendation | Why it matters |
|---|---|---|---|
| D1 | **Auth provider** | Microsoft Entra ID (Azure AD) SSO via Supabase OAuth | Org already has it; matches SharePoint identities; avoids a separate password store. Drives RLS via `auth.jwt() ->> 'email'` or a `users` table seeded from the IdP. |
| D2 | **Multi-tenancy model** | Single Supabase project, `facility_id` foreign key on every table, RLS policies enforce `user.facility_ids @> ARRAY[row.facility_id]` | Cheapest to operate; easiest cross-facility reporting. Switch to schema-per-facility only if a regulator requires hard isolation. |
| D3 | **Where formulas live** | Postgres (views for derived values, RPC functions for upload-side calculations) | One source of truth for Power BI + React + exports. Client only formats. The trade is slower iteration on formula changes — mitigate with a `db/formulas.sql` file under version control + migrations. |
| D4 | **Hosting** | Vercel for the React app, Supabase Cloud for the DB. GitHub Actions for CI. | Same git → deploy story; Vercel preview URLs per PR are free QA. |
| D5 | **Payroll ingestion path** | Supabase **Edge Function** that accepts the parsed Workday rows and upserts. Power Automate is retired. | Keeps the parsing logic next to the schema; removes a flaky integration; lets us add validation. Browser still uploads the .xlsx — we parse with `xlsx` in the Edge Function rather than client-side. |
| D6 | **History / audit** | `daily_snapshot_history` table populated by a trigger on every UPDATE. | We currently *overwrite* daily rows (see `docs/sharepoint-upsert-flow.md`). Auditors will ask "what did the 4/15 census look like before someone corrected it?" — answer is in history. |
| D7 | **Configurable units & fixed departments** | Make `UNITS` and `FIXED_DEPTS` data, not code. Tables: `units`, `fixed_departments`. Staffing grids stay code (rare changes, version-controlled). | New facility onboarding becomes a data load, not a deploy. |
| D8 | **Frontend stack details** | Vite + React 18 + TypeScript + Tailwind + shadcn/ui + TanStack Query + Recharts | Boring, well-documented, free. shadcn gives Tailwind components without lock-in; TanStack Query handles Supabase cache invalidation cleanly. |

---

## 3. Target data model (overview — full SQL in step a)

Eleven core tables. Names are lowercase snake_case, primary keys are `bigint
generated always as identity` unless otherwise noted, every table has
`created_at`, `updated_at`, `facility_id`.

```
facilities                 -- one row per facility (Highland is row 1)
users                      -- mirror of auth.users with role + facility_ids[]
units                      -- replaces UNITS array; per-facility
fixed_departments          -- replaces FIXED_DEPTS array; per-facility
staffing_grids             -- (facility_id, type, census, shift, role, count)

daily_snapshots            -- one row per (facility_id, time_entry_date)
                              the "model" side: census, NP%, obs hours, notes
unit_daily_census          -- one row per (snapshot_id, unit_id)
                              census + obs hrs + obs notes + np% per unit

payroll_periods            -- one row per (facility_id, start, end, file_name)
payroll_unit_actuals       -- (period_id, unit_id) hours/HC/OT/NP/wages
payroll_fixed_actuals      -- (period_id, fixed_dept_id) hours/HC/wages

mtd_periods                -- EPOB & Labor Mgmt page MTD inputs
mtd_unit_actuals           -- per-unit MTD numbers + budget FTE

daily_snapshot_history     -- audit log, written by trigger
```

**Views (derived — do not store):**
- `v_unit_staffing` — applies the grid to each `unit_daily_census` row, returns
  shift-level RN/LPN/Tech counts. Implements §1.3, §1.4, §2.3, §2.4.
- `v_daily_metrics` — joins census + payroll, computes occupancy, float FTE,
  variable/fixed/grand FTE, EPOB. Implements §2.5–§2.14.
- `v_unit_variance` — payroll vs model variance per unit per period.
  Implements §2.19–§2.23.
- `v_mtd_summary` — what the EPOB page reads.

**RPC functions (callable from client):**
- `push_daily_snapshot(jsonb)` — replaces the Power Automate webhook. Validates,
  upserts, fires history trigger.
- `ingest_payroll(period jsonb, rows jsonb[])` — called by the Edge Function
  after parsing the Workday Excel.
- `recalc_mtd(period_id)` — refreshes derived numbers when MTD inputs change.

The schema must round-trip every field listed in
`powerautomate-trigger-schema.json` so existing Power BI reports keep working
once they're repointed.

---

## 4. Phased migration

Each phase is shippable on its own. Phase N+1 must not break Phase N.

### Phase 0 — Foundations (1–2 days)

- [ ] Decide D1–D8 above. **Blocking for everything else.**
- [ ] Create Supabase project (`staffing-matrix-prod`) and a `staging` project.
- [ ] Create new repo layout in this same repo:
  ```
  /                       (existing prototype HTML — untouched)
  /db                     (migrations + seeds + formulas)
  /functions              (Supabase Edge Functions)
  /app                    (Vite + React + TS + Tailwind)
  /docs                   (this plan + ADRs)
  ```
- [ ] Wire GitHub Actions: lint + typecheck + `supabase db push --dry-run`
  on PRs.

### Phase 1 — Schema + RPCs (deliverable a) (3–5 days)

- [ ] Migrations under `/db/migrations/` create tables in §3.
- [ ] Seed Highland's `facilities`, `units`, `fixed_departments`,
  `staffing_grids` from `DATA_DICTIONARY_AND_FORMULAS.md` §1.1, §1.3–1.5.
- [ ] Implement views and RPCs. Each formula in the data dictionary maps to a
  named SQL expression in `/db/formulas.sql` with a comment citing the §
  number.
- [ ] **Verification gate:** load the existing
  `powerautomate-sample-payload.json` via `push_daily_snapshot()`; query
  `v_daily_metrics`; assert every numeric field matches the payload to ±0.05.
  This is the proof the rewrite preserves the math. Commit the test under
  `/db/tests/parity_2026-03-15.sql`.

### Phase 2 — App scaffold + read-only Data Entry page (deliverable b) (1 week)

- [ ] `/app` scaffolded with Vite, React 18, TS, Tailwind, shadcn/ui,
  TanStack Query, react-router, Supabase JS client.
- [ ] Auth wired (D1) with a login page and a `useFacility()` hook.
- [ ] Implement only the **Data Entry** page first — the busiest page in the
  prototype. **Read-only**: shows today's snapshot pulled from Supabase, no
  editing yet. Side-by-side test: prototype and React app open against the
  same date, every cell matches.
- [ ] Deploy preview URL. Share with one or two ops users for sanity check.

### Phase 3 — Writes + payroll ingestion (1–2 weeks)

- [ ] Data Entry page becomes editable. Saves via `push_daily_snapshot()`.
- [ ] Edge Function `ingest_payroll`: accepts a parsed Workday `.xlsx`,
  validates, calls `ingest_payroll()` RPC.
- [ ] Retire the Power Automate "Push to SharePoint" flow for new dates;
  SharePoint becomes a *consumer* (one-way mirror via a scheduled Edge
  Function) so Power BI keeps reading what it reads today.
- [ ] Migrate the historical SharePoint list into Supabase (one-time backfill
  job in `/db/backfill/`).

### Phase 4 — Remaining pages (2–3 weeks)

Port in this order, smaller pages first to validate the component library:

1. EPOB & Labor Management (the standalone `epob_labor_management.html`)
2. Variance
3. Position Control
4. Staffing
5. Trends
6. Executive Summary

Each page = one PR with: route, query hooks, components, screenshot diff vs
the prototype attached to the PR description.

### Phase 5 — Multi-facility rollout (timeline depends on org)

- [ ] Add the second facility's row to `facilities`, seed its `units` and
  `fixed_departments`. **No code changes** — that's the test that D2 was done
  right.
- [ ] Update RLS policies if the new facility has different role boundaries.
- [ ] Train facility admins on the React app; retire prototype HTML for that
  facility.

### Phase 6 — Decommission (after all facilities cut over)

- [ ] Move `index.html` and `epob_labor_management.html` to `/legacy/`.
- [ ] Delete the SharePoint list (after a 90-day archive snapshot).
- [ ] Delete Power Automate flows.

---

## 5. Risk register

| Risk | Likelihood | Mitigation |
|---|---|---|
| Formula drift between prototype and rewrite | High | Phase 1 parity gate; run the parity test in CI on every migration. |
| Ops team rejects new UI | Medium | Read-only side-by-side period in Phase 2 *before* asking anyone to switch. |
| Power BI breaks during cutover | Medium | Phase 3 keeps SharePoint as a one-way mirror. Power BI repointed in Phase 4 once schema is stable. |
| RLS misconfigured → data leak across facilities | Low/High | Write policy tests under `/db/tests/rls_*.sql`. Every new table needs a denial test. |
| Workday Excel format changes | Medium | Edge Function logs raw payload to a `payroll_raw_uploads` bucket; we can replay. |
| Single Supabase project becomes a SPOF | Low | Daily backups (Supabase built-in); restore drill once per quarter. |

---

## 6. What gets built first, concretely

If you approve this plan, the next two PRs are:

1. **PR #1 — schema + parity test.** Adds `/db/migrations/0001_init.sql`,
   `/db/seeds/highland.sql`, `/db/formulas.sql`,
   `/db/tests/parity_2026-03-15.sql`. No app code yet. Reviewable in isolation.
2. **PR #2 — app scaffold + read-only Data Entry.** Adds `/app`, deploys a
   preview URL. Auth, one page, read-only. Reviewable in isolation.

After PR #2 lands, we re-plan the remaining pages with whatever we've learned.

---

## 7. Open questions for you

1. Confirm D1 (Entra ID SSO). If the org doesn't have it, magic-link is the
   fallback — say which.
2. Are there facilities besides Highland we know about *now*? Even just names
   helps shape `facilities` seeds.
3. Who's the second pair of eyes on the parity gate — i.e., who signs off that
   the React numbers match the prototype? (Probably the ops lead who's been
   using the SharePoint flow.)
4. Do you want Power BI repointed to Supabase as part of Phase 3, or kept on
   SharePoint until Phase 4? (Affects the mirror's lifetime.)
5. Branch & deploy strategy: PRs into `main` with Vercel previews, or do you
   want a `develop` branch first?

Answer those and the next step is PR #1 (deliverable a).
