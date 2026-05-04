import { useQuery } from '@tanstack/react-query'
import { supabase } from './supabase'
import type { Database } from './database.types'

type Unit       = Database['public']['Tables']['units']['Row']
type Snapshot   = Database['public']['Tables']['daily_snapshots']['Row']
type UnitCensus = Database['public']['Tables']['unit_daily_census']['Row']
type Daily      = Database['public']['Views']['v_daily_metrics']['Row']
type Grand      = Database['public']['Views']['v_grand_metrics']['Row']
type UnitTotals = Database['public']['Views']['v_snapshot_unit_totals']['Row']

export type DataEntryView = {
  facility:    { id: number; slug: string; name: string; total_staffed_beds: number }
  units:       Unit[]
  snapshot:    Snapshot | null
  unitCensus:  (UnitCensus & { unit_key: string })[]
  unitTotals:  UnitTotals[]
  daily:       Daily | null
  grand:       Grand | null
}

export function useDataEntry(facilitySlug: string, dateISO: string) {
  return useQuery<DataEntryView>({
    queryKey: ['data-entry', facilitySlug, dateISO],
    enabled: Boolean(supabase),
    queryFn: async () => {
      if (!supabase) throw new Error('Supabase not configured')

      const { data: facility, error: fErr } = await supabase
        .from('facilities')
        .select('id, slug, name, total_staffed_beds')
        .eq('slug', facilitySlug)
        .single()
      if (fErr || !facility) throw fErr ?? new Error('Facility not found')

      const { data: units = [], error: uErr } = await supabase
        .from('units')
        .select('*')
        .eq('facility_id', facility.id)
        .eq('active', true)
        .order('sort_order')
      if (uErr) throw uErr

      const { data: snapshot } = await supabase
        .from('daily_snapshots')
        .select('*')
        .eq('facility_id', facility.id)
        .eq('time_entry_date', dateISO)
        .maybeSingle()

      if (!snapshot) {
        return { facility, units: units ?? [], snapshot: null, unitCensus: [], unitTotals: [], daily: null, grand: null }
      }

      const [unitCensusRes, unitTotalsRes, dailyRes, grandRes] = await Promise.all([
        supabase.from('unit_daily_census')
          .select('*, units!inner(key)')
          .eq('snapshot_id', snapshot.id),
        supabase.from('v_snapshot_unit_totals')
          .select('*')
          .eq('snapshot_id', snapshot.id),
        supabase.from('v_daily_metrics')
          .select('*')
          .eq('snapshot_id', snapshot.id)
          .single(),
        supabase.from('v_grand_metrics')
          .select('*')
          .eq('snapshot_id', snapshot.id)
          .single(),
      ])

      type CensusWithUnit = UnitCensus & { units: { key: string } | null }
      const unitCensus = ((unitCensusRes.data ?? []) as CensusWithUnit[]).map((r) => ({
        ...r,
        unit_key: r.units?.key ?? '',
      }))

      return {
        facility,
        units: units ?? [],
        snapshot,
        unitCensus,
        unitTotals: unitTotalsRes.data ?? [],
        daily: dailyRes.data ?? null,
        grand: grandRes.data ?? null,
      }
    },
  })
}
