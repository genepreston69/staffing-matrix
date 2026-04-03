# Highland Staffing Matrix — Dashboard Layouts

You have the SharePoint data loaded. Follow these steps to build 3 dashboards.

## Prerequisites

Before building dashboards, you need:
1. **DateTable** — Modeling > New Table > paste formula from `queries/04_DateTable.dax`
2. **Mark as Date Table** — Select DateTable > Table Tools > Mark as Date Table > pick `Date`
3. **Relationship** — Model view > drag `DateTable[Date]` onto `StaffingData[TimeEntryDateKey]`
   - `TimeEntryDate` is the actual census/payroll date; `Date` is just when data was pushed to SharePoint
4. **All DAX Measures** — paste each from `queries/05_DAX_Measures.dax` via Modeling > New Measure

---

## Dashboard 1: DAILY SNAPSHOT

**Purpose:** Single-day view of all staffing metrics. User picks a date with the slicer.

### Page Setup
- Add new page, name it **Daily Snapshot**
- Add a **Date Slicer** (single-select mode): drag `DateTable[Date]`, set to "List" or "Dropdown"

### Row 1 — Facility KPI Cards (top of page)
| Card | Measure | Format |
|------|---------|--------|
| Total Census | `Daily Total Census` | #,0 |
| Occupancy % | `Daily Occupancy %` | 0.0 |
| DC EPOB | `Daily DC EPOB` | 0.00 |
| Total EPOB | `Daily Total EPOB` | 0.00 |
| Variable FTE | `Daily Variable FTE` | 0.0 |
| Grand FTE | `Daily Grand FTE` | 0.0 |
| OT Hours | `Daily OT Hours` | 0.0 |

### Row 2 — Census by Unit (Cards or Matrix)
| Card | Measure |
|------|---------|
| 1 East | `Daily Census 1East` |
| 2 East | `Daily Census 2East` |
| 2 West | `Daily Census 2West` |
| 3 East | `Daily Census 3East` |
| 3 West | `Daily Census 3West` |
| HRC | `Daily Census HRC` |

**Subtitle each card** with the occupancy: `Daily Occ% 1East`, etc.

### Row 3 — Staffing Detail Table
Add a **Table** visual with these columns from StaffingData:
- `1East_Day_RN`, `1East_Day_LPN`, `1East_Day_Tech`
- `1East_Evening_RN`, `1East_Evening_LPN`, `1East_Evening_Tech`
- `1East_Night_RN`, `1East_Night_LPN`, `1East_Night_Tech`
- Repeat for each unit, or use a **Matrix** visual with unit on rows

### Row 4 — Payroll Variance (when payroll data exists)
| Card | Measure |
|------|---------|
| Actual Hours | `Daily Actual Hours` |
| Model Hours | `Daily Model Hours` |
| Variance | `Daily Hours Variance` |
| Variance % | `Daily Variance %` |
| Actual DC EPOB | `Daily Actual DC EPOB` |
| EPOB Variance | `Daily EPOB DC Variance` |

### Row 5 — Unit Variance Table
Add a **Table** visual with per-unit variance measures:
| Column Header | Measure |
|---------------|---------|
| 1East Var | `Daily Var Hrs 1East` |
| 2East Var | `Daily Var Hrs 2East` |
| 2West Var | `Daily Var Hrs 2West` |
| 3East Var | `Daily Var Hrs 3East` |
| 3West Var | `Daily Var Hrs 3West` |
| HRC Var | `Daily Var Hrs HRC` |

---

## Dashboard 2: MONTHLY (MTD AVG DAILY CENSUS)

**Purpose:** Month-level averages based on Average Daily Census. Select any date to view that month.

### Page Setup
- Add new page, name it **Monthly Dashboard**
- Add a **Date Slicer** (set to "Between" or use `DateTable[YearMonth]` as a dropdown)

### Section A — Facility Monthly Summary (Cards)
| Card | Measure |
|------|---------|
| MTD Avg Daily Census | `MTD Avg Daily Census` |
| MTD Avg Occupancy % | `MTD Avg Occupancy %` |
| MTD Avg DC EPOB | `MTD Avg DC EPOB` |
| MTD Avg Total EPOB | `MTD Avg Total EPOB` |
| MTD Avg Grand FTE | `MTD Avg Grand FTE` |
| MTD Total OT Hours | `MTD Total OT Hours` |
| MTD Days Count | `MTD Days Count` |

### Section B — Month vs Prior Month (Cards)
| Card | Measure |
|------|---------|
| Prior Month Avg Census | `Prior Month Avg Census` |
| Change vs Prior | `MTD vs Prior Month Census` |
| Change % | `MTD vs Prior Month %` |

### Section C — Monthly Census by Unit (Table or Cards)

**Option A: Table visual**
| Column | Measure |
|--------|---------|
| 1 East Census | `MTD Avg Census 1East` |
| 1 East Occ% | `MTD Avg Occ% 1East` |
| 2 East Census | `MTD Avg Census 2East` |
| 2 East Occ% | `MTD Avg Occ% 2East` |
| 2 West Census | `MTD Avg Census 2West` |
| 2 West Occ% | `MTD Avg Occ% 2West` |
| 3 East Census | `MTD Avg Census 3East` |
| 3 East Occ% | `MTD Avg Occ% 3East` |
| 3 West Census | `MTD Avg Census 3West` |
| 3 West Occ% | `MTD Avg Occ% 3West` |
| HRC Census | `MTD Avg Census HRC` |
| HRC Occ% | `MTD Avg Occ% HRC` |

**Option B: 6 Card visuals** (one per unit showing avg census + occupancy %)

### Section D — Monthly OT by Unit (Clustered Bar Chart)
- Axis: static text labels (use a table visual instead if easier)
- Values: `MTD OT 1East`, `MTD OT 2East`, `MTD OT 2West`, `MTD OT 3East`, `MTD OT 3West`, `MTD OT HRC`

### Section E — Monthly Staffing Trend (Line Chart)
- Axis: `DateTable[Date]`
- Values: `Daily Total Census` (shows daily census within the month)
- Add reference line at `MTD Avg Daily Census` value (Analytics pane > Constant Line)

---

## Dashboard 3: YTD (YEAR-TO-DATE AVG DAILY CENSUS)

**Purpose:** Year-level averages. Shows cumulative Average Daily Census for the year.

### Page Setup
- Add new page, name it **YTD Dashboard**
- Add a **Year Slicer**: drag `DateTable[Year]` as a dropdown

### Section A — Facility YTD Summary (Cards)
| Card | Measure |
|------|---------|
| YTD Avg Daily Census | `YTD Avg Daily Census` |
| YTD Avg Occupancy % | `YTD Avg Occupancy %` |
| YTD Avg DC EPOB | `YTD Avg DC EPOB` |
| YTD Avg Total EPOB | `YTD Avg Total EPOB` |
| YTD Avg Grand FTE | `YTD Avg Grand FTE` |
| YTD Total OT Hours | `YTD Total OT Hours` |
| YTD Days Count | `YTD Days Count` |

### Section B — YTD Census by Unit (Table)
| Column | Measure |
|--------|---------|
| 1 East Avg Census | `YTD Avg Census 1East` |
| 1 East Avg Occ% | `YTD Avg Occ% 1East` |
| 2 East Avg Census | `YTD Avg Census 2East` |
| 2 East Avg Occ% | `YTD Avg Occ% 2East` |
| 2 West Avg Census | `YTD Avg Census 2West` |
| 2 West Avg Occ% | `YTD Avg Occ% 2West` |
| 3 East Avg Census | `YTD Avg Census 3East` |
| 3 East Avg Occ% | `YTD Avg Occ% 3East` |
| 3 West Avg Census | `YTD Avg Census 3West` |
| 3 West Avg Occ% | `YTD Avg Occ% 3West` |
| HRC Avg Census | `YTD Avg Census HRC` |
| HRC Avg Occ% | `YTD Avg Occ% HRC` |

### Section C — YTD OT by Unit
Same pattern as Monthly but with `YTD OT 1East` through `YTD OT HRC`

### Section D — Monthly Trend Within Year (Line Chart)
- Axis: `DateTable[YearMonth]`
- Values: `MTD Avg Daily Census`
- This shows how the monthly average census changes month-over-month through the year

### Section E — Monthly Trend by Unit (Small Multiples or Multiple Lines)
- Axis: `DateTable[YearMonth]`
- Values: `MTD Avg Census 1East`, `MTD Avg Census 2East`, `MTD Avg Census 2West`, `MTD Avg Census 3East`, `MTD Avg Census 3West`, `MTD Avg Census HRC`
- Use different line colors per unit

---

## Measure Summary (108 total)

| Folder | Count | Scope |
|--------|-------|-------|
| Daily - Facility | 26 | Snapshot: census, staffing, FTE, EPOB, variance, OT |
| Daily - By Unit | 30 | Per-unit census, occupancy, staffing, variance, OT |
| MTD - Facility | 15 | Monthly averages: census, EPOB, FTE, staff, OT, variance |
| MTD - By Unit | 18 | Per-unit monthly avg census, occupancy, OT |
| MTD - Comparisons | 3 | Prior month avg census, change, change % |
| YTD - Facility | 11 | Year-to-date averages: census, EPOB, FTE, OT, variance |
| YTD - By Unit | 18 | Per-unit YTD avg census, occupancy, OT |
| **Total** | **121** | |

---

## Conditional Formatting Tips

For variance measures, apply conditional formatting:
1. Select the visual > Format > Conditional Formatting
2. **Positive variance** (overstaffed): Red background
3. **Negative variance** (understaffed): Orange/Yellow background
4. **Near zero** (balanced): Green background

For EPOB:
- DC EPOB > 1.2 = Red (high)
- DC EPOB 0.9–1.2 = Green (target range)
- DC EPOB < 0.9 = Yellow (low)
