# Staffing Matrix — React app

Vite + React 19 + TypeScript + Tailwind + TanStack Query, talking to the
Supabase backend in `../db`. Phase 2 of `docs/supabase-migration-plan.md`.

## Quick start

```bash
cd app
cp .env.example .env.local         # fill in Supabase URL + anon key
npm install
npm run dev                        # http://localhost:5173
```

Without `.env.local` the app still runs but pages show a configuration banner.

## Layout

```
app/
├── index.html                 Vite entry
├── src/
│   ├── main.tsx               Router + Query + Auth providers
│   ├── App.tsx                Route table (auth gate, layout)
│   ├── index.css              Tailwind directives + base
│   ├── lib/
│   │   ├── supabase.ts        Singleton client (null when unconfigured)
│   │   ├── database.types.ts  Hand-written subset; replace with `supabase gen types typescript`
│   │   ├── auth.tsx           AuthProvider + useAuth (magic-link)
│   │   └── queries.ts         TanStack Query hooks (useDataEntry)
│   └── pages/
│       ├── LoginPage.tsx      Magic-link form
│       ├── AppLayout.tsx      Sidebar + outlet
│       └── DataEntryPage.tsx  Read-only census + KPI view (Phase 2 deliverable)
├── tailwind.config.js
└── postcss.config.js
```

## What's implemented (Phase 2)

- Auth gate using Supabase magic-link (D1).
- App shell with sidebar; only **Data Entry** is wired, the rest are stubs.
- Data Entry **read-only**: queries `daily_snapshots`, `unit_daily_census`,
  `v_snapshot_unit_totals`, `v_daily_metrics`, `v_grand_metrics` for the
  selected date. Renders a per-unit table plus KPI tiles.

## What comes next (Phase 3 in the plan)

- Make Data Entry editable; wire to `push_daily_snapshot()` RPC.
- Edge Function for payroll ingestion (`functions/ingest_payroll`).
- Port remaining pages (Variance, Trends, Position Control, Staffing,
  Executive Summary, EPOB & Labor Mgmt).
- Replace `database.types.ts` with generated types.

## Type generation (when ready)

```bash
supabase login
supabase link --project-ref <ref>
supabase gen types typescript --linked > src/lib/database.types.ts
```
