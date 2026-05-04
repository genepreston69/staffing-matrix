// Hand-written subset of the Supabase schema. Replace with generated types
// (`supabase gen types typescript`) once the project is linked. Each Tables
// entry needs Row + Insert + Update + Relationships for supabase-js typing
// to flow through .select() / .insert(); for Phase 2 we mirror Row.

type Tbl<R> = { Row: R; Insert: Partial<R>; Update: Partial<R>; Relationships: [] }
type View<R> = { Row: R; Relationships: [] }

export type Database = {
  public: {
    Tables: {
      facilities: Tbl<{
        id: number
        slug: string
        name: string
        total_staffed_beds: number
        fte_multiplier: number
        default_np_pct: number
        baseline_salary_fte: number
        active: boolean
      }>
      units: Tbl<{
        id: number
        facility_id: number
        code: string
        key: string
        payroll_bu: string
        type: 'acute' | 'detox'
        max_beds: number
        label: string
        sort_order: number
        active: boolean
      }>
      daily_snapshots: Tbl<{
        id: number
        facility_id: number
        time_entry_date: string
        np_model_pct: number
        payroll_period_id: number | null
        fixed_source: 'baseline' | 'payroll' | 'mtd'
        notes: string | null
      }>
      unit_daily_census: Tbl<{
        id: number
        snapshot_id: number
        unit_id: number
        census: number
        obs_hours: number
        obs_notes: string
        np_pct: number | null
      }>
    }
    Views: {
      v_daily_metrics: View<{
        snapshot_id: number
        facility_id: number
        time_entry_date: string
        np_model_pct: number
        total_census: number
        occupancy_pct: number
        total_rn: number
        total_lpn: number
        total_tech: number
        total_shift_staff: number
        float_shift_positions: number
        rn_prod_fte: number
        rn_adj_fte: number
        lpn_prod_fte: number
        lpn_adj_fte: number
        tech_prod_fte: number
        tech_adj_fte: number
        float_prod_fte: number
        float_adj_fte: number
        oneone_prod_fte: number
        oneone_adj_fte: number
        var_prod_fte: number
        var_adj_fte: number
      }>
      v_grand_metrics: View<{
        snapshot_id: number
        facility_id: number
        time_entry_date: string
        total_census: number
        var_prod_fte: number
        var_adj_fte: number
        fixed_fte: number
        fixed_hc: number
        grand_prod_fte: number
        grand_adj_fte: number
        epob_direct_care: number | null
        epob_total_facility: number | null
      }>
      v_snapshot_unit_totals: View<{
        unit_daily_id: number
        snapshot_id: number
        unit_id: number
        facility_id: number
        time_entry_date: string
        unit_key: string
        payroll_bu: string
        unit_type: 'acute' | 'detox'
        census: number
        max_beds: number
        obs_hours: number
        np_pct: number
        unit_occupancy_pct: number
        total_rn_positions: number
        total_lpn_positions: number
        total_tech_positions: number
        total_shift_positions: number
        model_daily_hours: number
      }>
    }
    Functions: Record<string, never>
    Enums: Record<string, never>
    CompositeTypes: Record<string, never>
  }
}
