import { useMemo, useState } from 'react'
import { useDataEntry } from '../lib/queries'
import { isSupabaseConfigured } from '../lib/supabase'
import type { Database } from '../lib/database.types'

type UnitTotals = Database['public']['Views']['v_snapshot_unit_totals']['Row']

const FACILITY_SLUG = 'highland'
const todayISO = () => new Date().toISOString().slice(0, 10)

function fmt(n: number | null | undefined, digits = 1) {
  if (n === null || n === undefined) return '—'
  return Number(n).toFixed(digits)
}

export default function DataEntryPage() {
  const [date, setDate] = useState(todayISO())
  const { data, isLoading, error } = useDataEntry(FACILITY_SLUG, date)

  const censusByUnitId = useMemo(() => {
    const m = new Map<number, { census: number; obs_hours: number; obs_notes: string }>()
    data?.unitCensus.forEach((c) => m.set(c.unit_id, c))
    return m
  }, [data])

  const unitTotalsByUnitId = useMemo(() => {
    const m = new Map<number, UnitTotals>()
    data?.unitTotals.forEach((t) => m.set(t.unit_id, t))
    return m
  }, [data])

  if (!isSupabaseConfigured) {
    return (
      <div className="max-w-3xl mx-auto rounded border border-amber-300 bg-amber-50 px-4 py-3 text-sm text-amber-900">
        Supabase isn't configured. Set <code>VITE_SUPABASE_URL</code> and{' '}
        <code>VITE_SUPABASE_ANON_KEY</code> in <code>app/.env.local</code> and restart the dev server.
      </div>
    )
  }

  return (
    <div className="space-y-6">
      <header className="flex items-end justify-between gap-4 flex-wrap">
        <div>
          <h1 className="text-2xl font-semibold text-slate-900">
            Census-Driven Staffing <span className="text-slate-500">& Position Control</span>
          </h1>
          <p className="text-sm text-slate-500">
            Read-only preview from Supabase. Editing arrives in Phase 3.
          </p>
        </div>
        <label className="text-sm">
          <span className="block text-xs font-medium text-slate-600 mb-1">Time Entry Date</span>
          <input
            type="date"
            value={date}
            onChange={(e) => setDate(e.target.value)}
            className="rounded-md border-slate-300 focus:border-teal focus:ring-teal text-sm"
          />
        </label>
      </header>

      {isLoading && <p className="text-sm text-slate-500">Loading…</p>}
      {error && <p className="text-sm text-red-600">{(error as Error).message}</p>}

      {data && !data.snapshot && (
        <div className="rounded border border-slate-200 bg-white p-4 text-sm text-slate-600">
          No snapshot for {date}. Pick another date or, in Phase 3, create one.
        </div>
      )}

      {data?.snapshot && data.daily && data.grand && (
        <>
          {/* KPI strip */}
          <section className="grid grid-cols-2 md:grid-cols-4 gap-3">
            <Kpi label="Census" value={`${data.daily.total_census}`} sub={`${fmt(data.daily.occupancy_pct)}% of ${data.facility.total_staffed_beds}`} />
            <Kpi label="Variable Adj FTE" value={fmt(data.daily.var_adj_fte)} sub={`Prod ${fmt(data.daily.var_prod_fte)}`} />
            <Kpi label="DC EPOB" value={fmt(data.grand.epob_direct_care, 2)} sub="Variable Adj FTE / Census" />
            <Kpi label="Total EPOB" value={fmt(data.grand.epob_total_facility, 2)} sub={`Grand ${fmt(data.grand.grand_adj_fte)}`} />
          </section>

          {/* Per-unit table */}
          <section className="bg-white rounded-lg border border-slate-200 overflow-hidden">
            <table className="w-full text-sm">
              <thead className="bg-slate-50 text-slate-600 text-xs uppercase tracking-wide">
                <tr>
                  <th className="text-left px-3 py-2">Unit</th>
                  <th className="text-right px-3 py-2">Census</th>
                  <th className="text-right px-3 py-2">Beds</th>
                  <th className="text-right px-3 py-2">Occ %</th>
                  <th className="text-right px-3 py-2">RN</th>
                  <th className="text-right px-3 py-2">LPN</th>
                  <th className="text-right px-3 py-2">Tech</th>
                  <th className="text-right px-3 py-2">Shift Pos</th>
                  <th className="text-right px-3 py-2">Obs Hrs</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-100">
                {data.units.map((u) => {
                  const c = censusByUnitId.get(u.id)
                  const t = unitTotalsByUnitId.get(u.id)
                  return (
                    <tr key={u.id}>
                      <td className="px-3 py-2 font-medium text-slate-900">{u.label}</td>
                      <td className="px-3 py-2 text-right tabular-nums">{c?.census ?? 0}</td>
                      <td className="px-3 py-2 text-right tabular-nums text-slate-500">{u.max_beds}</td>
                      <td className="px-3 py-2 text-right tabular-nums">{t ? fmt(t.unit_occupancy_pct, 0) : '—'}</td>
                      <td className="px-3 py-2 text-right tabular-nums">{t?.total_rn_positions ?? '—'}</td>
                      <td className="px-3 py-2 text-right tabular-nums">{t?.total_lpn_positions ?? '—'}</td>
                      <td className="px-3 py-2 text-right tabular-nums">{t?.total_tech_positions ?? '—'}</td>
                      <td className="px-3 py-2 text-right tabular-nums font-semibold">{t?.total_shift_positions ?? '—'}</td>
                      <td className="px-3 py-2 text-right tabular-nums">{c?.obs_hours ?? 0}</td>
                    </tr>
                  )
                })}
                <tr className="bg-slate-50 font-semibold">
                  <td className="px-3 py-2">Totals</td>
                  <td className="px-3 py-2 text-right tabular-nums">{data.daily.total_census}</td>
                  <td className="px-3 py-2 text-right tabular-nums text-slate-500">{data.facility.total_staffed_beds}</td>
                  <td className="px-3 py-2 text-right tabular-nums">{fmt(data.daily.occupancy_pct)}</td>
                  <td className="px-3 py-2 text-right tabular-nums">{data.daily.total_rn}</td>
                  <td className="px-3 py-2 text-right tabular-nums">{data.daily.total_lpn}</td>
                  <td className="px-3 py-2 text-right tabular-nums">{data.daily.total_tech}</td>
                  <td className="px-3 py-2 text-right tabular-nums">{data.daily.total_shift_staff}</td>
                  <td className="px-3 py-2 text-right tabular-nums">
                    {data.unitCensus.reduce((s, c) => s + Number(c.obs_hours), 0)}
                  </td>
                </tr>
              </tbody>
            </table>
          </section>

          {/* FTE breakdown */}
          <section className="grid grid-cols-2 md:grid-cols-4 gap-3">
            <Kpi label="RN FTE (adj)" value={fmt(data.daily.rn_adj_fte)} sub={`Prod ${fmt(data.daily.rn_prod_fte)}`} />
            <Kpi label="LPN FTE (adj)" value={fmt(data.daily.lpn_adj_fte)} sub={`Prod ${fmt(data.daily.lpn_prod_fte)}`} />
            <Kpi label="Tech FTE (adj)" value={fmt(data.daily.tech_adj_fte)} sub={`Prod ${fmt(data.daily.tech_prod_fte)}`} />
            <Kpi label="Float / 1:1" value={`${fmt(data.daily.float_adj_fte)} / ${fmt(data.daily.oneone_adj_fte)}`} sub="Adj FTE" />
          </section>
        </>
      )}
    </div>
  )
}

function Kpi({ label, value, sub }: { label: string; value: string; sub?: string }) {
  return (
    <div className="bg-white rounded-lg border border-slate-200 px-4 py-3">
      <div className="text-xs uppercase tracking-wide text-slate-500">{label}</div>
      <div className="text-2xl font-semibold tabular-nums text-slate-900">{value}</div>
      {sub && <div className="text-xs text-slate-500">{sub}</div>}
    </div>
  )
}
