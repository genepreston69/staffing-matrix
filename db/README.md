# Database — Supabase backend

Source of truth for the rewrite (see `docs/supabase-migration-plan.md`).
Postgres 15+ / Supabase. The prototype HTML files at the repo root are
unaffected by anything in this directory.

## Layout

```
db/
├── migrations/            applied in lexical order
│   ├── 0001_init.sql      core + daily + payroll + mtd + history tables
│   ├── 0002_rls.sql       row-level security policies
│   ├── 0003_views.sql     v_unit_staffing, v_daily_metrics, v_unit_variance
│   └── 0004_rpcs.sql      push_daily_snapshot, ingest_payroll, recalc_mtd
├── seeds/
│   └── highland.sql       Highland facility (units, fixed_depts, grids)
└── tests/
    └── parity_2026-05-04.sql   verifies views match shared_staffing.json
```

## Decisions locked (from chat 2026-05-04)

| # | Decision |
|---|---|
| D1 | **Auth:** Supabase magic-link (email). |
| D2 | **Multi-tenancy:** single project; every table carries `facility_id`; RLS enforces access. |
| D3 | **Formulas:** Postgres views + RPCs. Client formats only. |
| D5 | **Payroll ingestion:** Supabase Edge Function (parses Workday `.xlsx`, calls `ingest_payroll` RPC). |
| D7 | **Configurable units & fixed depts:** tables, not code. Adding a facility = data load. |
| D4, D6, D8 | Defaults from plan §2 unless overridden: Vercel + Supabase Cloud; `daily_snapshot_history` audit trigger; Vite/React/TS/Tailwind/shadcn/TanStack Query. |

## Apply locally

Requires the Supabase CLI (`brew install supabase/tap/supabase`) and Docker.

```bash
# one-time
supabase init
supabase start

# apply schema + seed Highland
psql "$SUPABASE_DB_URL" -f db/migrations/0001_init.sql
psql "$SUPABASE_DB_URL" -f db/migrations/0002_rls.sql
psql "$SUPABASE_DB_URL" -f db/migrations/0003_views.sql
psql "$SUPABASE_DB_URL" -f db/migrations/0004_rpcs.sql
psql "$SUPABASE_DB_URL" -f db/seeds/highland.sql

# run parity test (errors if any assertion fails)
psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f db/tests/parity_2026-05-04.sql
```

When we wire CI (Phase 0 of the plan) the parity test runs on every PR.

## Conventions

- All tables: `id bigint generated always as identity primary key`,
  `facility_id bigint not null references facilities(id)`,
  `created_at timestamptz not null default now()`,
  `updated_at timestamptz not null default now()`.
- Names: `lower_snake_case`. Views prefixed `v_`. RPCs are verbs.
- Money in `numeric(12,2)`. Hours/FTE in `numeric(10,2)`. Percentages stored
  as numbers (12.6, not 0.126).
- Every formula in `DATA_DICTIONARY_AND_FORMULAS.md` §2 is implemented in a
  view and tagged with the section number in a SQL comment.

## Open follow-ups

The plan's §7 questions are still open and don't block schema work, but
will shape later phases:

1. Other facilities to seed (Highland is the only one in `seeds/highland.sql`
   today).
2. Who signs off on the parity gate.
3. Power BI cutover timing.
4. Branch & deploy strategy.
