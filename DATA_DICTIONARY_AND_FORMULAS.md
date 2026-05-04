# Highland Hospital Staffing Matrix -- Data Dictionary & Formula Reference

> Auto-generated from `index.html` source analysis.

---

## 1. Data Dictionary

### 1.1 Unit Configuration (`UNITS` array -- line 399)

Each object represents one inpatient nursing unit.

| Field | Type | Description | Example |
|---|---|---|---|
| `id` | string | Unique DOM / lookup key | `u100e` |
| `payrollBU` | string | Business-unit name used to match payroll upload rows | `Acute Adult-100E` |
| `type` | string | Unit classification -- determines which staffing grid to use (`acute` or `detox`) | `acute` |
| `maxBeds` | integer | Licensed bed capacity of the unit | `18` |
| `label` | string | Human-readable display name shown in the UI | `1 East - Child Acute` |

**Current units:**

| ID | Payroll BU | Type | Max Beds | Label |
|---|---|---|---|---|
| `u100e` | Acute Adult-100E | acute | 18 | 1 East - Child Acute |
| `u200e` | Acute Child-200E | acute | 20 | 2 East - Adult Acute |
| `u200w` | Acute Adol-200W | acute | 20 | 2 West - Adolescent |
| `u300e` | Acute Adult-300E | acute | 20 | 3 East - Adult Acute |
| `u300w` | Acute Adult-300W | acute | 20 | 3 West - Adult Acute |
| `detox` | Acute Adult-100 | detox | 16 | HRC - SUD/Detox ASAM 3.7 |

---

### 1.2 Global Constants (line 407)

| Constant | Value | Description |
|---|---|---|
| `TOTAL_STAFFED` | 114 | Total licensed bed capacity across all units (sum of all `maxBeds`) |
| `FTE_MULTIPLIER` | 1.4 | Converts per-shift staff positions to FTE (accounts for 3 shifts/day plus coverage) |

---

### 1.3 Acute Care Staffing Grid (`ACUTE_GRID` -- lines 409-413)

Census-indexed arrays (index 0 = census of 1, index 19 = census of 20) specifying the number of RNs, LPNs, and Techs required per shift.

| Shift | RN Pattern (census 1-20) | LPN Pattern | Tech Pattern |
|---|---|---|---|
| **Day** | 1 for all census levels | 0 for census 1-13, 1 for 14-20 | 1 for census 1-10, mixed 1-2 for 11-20 |
| **Evening** | 1 for all census levels | 0 for census 1-13, 1 for 14-20 | 1 for census 1-10, mixed 1-2 for 11-20 |
| **Night** | 1 for all census levels | 0 for all census levels | 1 for census 1-15, 2 for 16-20 |

**Ratio notes:** Day/Eve 1:6, Night 1:7, plus float coverage.

---

### 1.4 Detox/ASAM Staffing Grid (`DETOX_GRID` -- lines 415-419)

Census-indexed arrays (index 0 = census of 1, index 15 = census of 16). LPN-based model with no RNs.

| Shift | RN | LPN | Tech |
|---|---|---|---|
| **Day** | 0 (all census) | 1 (all census) | 1 (all census) |
| **Evening** | 0 (all census) | 1 (all census) | 1 (all census) |
| **Night** | 0 (all census) | 1 (all census) | 1 (all census) |

**Ratio notes:** ASAM 3.7, LPN model, 1:8.

---

### 1.5 Fixed Departments (`FIXED_DEPTS` array -- lines 422-434)

Non-census-variable departments with baseline headcount and FTE allocations.

| Department | Category | Headcount (hc) | Baseline FTE |
|---|---|---|---|
| Intake | Clinical Operations | 19 | 14.5 |
| IP Clinical Administration | Clinical Operations | 9 | 7.6 |
| Case Management | Clinical Operations | 6 | 5.6 |
| Utilization Review | Clinical Operations | 4 | 3.3 |
| Recreation Therapy | Clinical Operations | 5 | 2.9 |
| IP Therapists | Clinical Operations | 12 | 2.4 |
| Medical Staff | Clinical Operations | 2 | 0.1 |
| Physician InPatient | Clinical Operations | 2 | 0.2 |
| Infection Control | Clinical Operations | 1 | 0.2 |
| Dietary | Support Services | 8 | 8.0 |
| Housekeeping | Support Services | 7 | 6.0 |
| Communications | Support Services | 3 | 2.5 |
| Plant Operations | Support Services | 4 | 2.4 |
| Medical Records | Support Services | 3 | 2.1 |
| Call Center | Support Services | 1 | 1.2 |
| Administration | Admin / G&A | 3 | 1.2 |
| Facility Accounting | Admin / G&A | 2 | 1.3 |
| Facility QI/Risk Mgmt | Admin / G&A | 3 | 1.5 |
| Human Resources | Admin / G&A | 2 | 0.1 |
| Business Office | Admin / G&A | 1 | 0.1 |
| Facility IT | Admin / G&A | 2 | 0.1 |

**Totals (computed at line 435-436):**
- `BASELINE_FIXED_FTE` = 63.3
- `BASELINE_FIXED_HC` = 98

---

### 1.6 Payroll Upload Data Structures (lines 437-438)

#### `payrollData` -- per business-unit payroll summary

Populated when a Workday/PayDay time-summary Excel file is uploaded.

| Field | Type | Description |
|---|---|---|
| `bu` | string | Business unit name |
| `hours` | number | Total paid hours in the period |
| `wages` | number | Total wages paid |
| `regHrs` | number | Regular (straight-time) hours |
| `otHrs` | number | Overtime hours |
| `npHrs` | number | Non-productive hours (PTO, sick, holiday, orientation, training, continuing education, jury duty, bereavement) |
| `headcount` | number | Count of unique workers |
| `fteSum` | number | Sum of FTE percentages / 100 |
| `jobs` | object | Map of `{jobName: {count, hours}}` -- breakdown by job title |

#### `payrollMeta` -- payroll file metadata

| Field | Type | Description |
|---|---|---|
| `fileName` | string | Name of the uploaded file |
| `dayCount` | number | Number of calendar days in the payroll period |
| `minDate` | Date | Earliest date in the dataset |
| `maxDate` | Date | Latest date in the dataset |
| `rowCount` | number | Number of data rows parsed |

#### Non-Productive Hour Categories (`NP_COL_NAMES` -- line 804)

Columns summed into `npHrs`:
- PTO Hours, Sick Hours, Holiday Hours, Orientation Hours, Training Hours, Continuing Education Hours, Education Pay Hours, Jury Duty Hours, Bereavement Hours

---

## 2. Formula Reference

### 2.1 Non-Productive Percentage

```
getNP() --> NP%    (line 529)
```

| Input | Default | Range |
|---|---|---|
| User-entered NP% | 12.6% | Clamped to 0--40% |

---

### 2.2 Gross-Up (NP Adjustment)

```
grossUp(productiveFTE) = productiveFTE / (1 - NP% / 100)    (line 532)
```

Converts productive FTE to adjusted FTE by adding non-productive time coverage.

**Example:** 10.0 prod FTE at 12.6% NP = 10.0 / 0.874 = **11.44 adj FTE**

The displayed multiplier (line 579):

```
NP Multiplier = 1 / (1 - NP% / 100)
```

---

### 2.3 Staffing Grid Lookup

```
getStaffing(grid, census)    (lines 518-526)
```

- Index = `min(census, grid length) - 1`
- Returns `{day, evening, night}` each containing `{rn, lpn, tech}` staff counts
- Census of 0 returns all zeros

---

### 2.4 Census Validation

```
census = min(max(inputValue, 0), maxBeds)    (line 570)
```

Clamps each unit's census between 0 and its licensed bed capacity.

---

### 2.5 Occupancy Percentages

**Unit occupancy (line 583):**

```
unitOccupancy% = round(census / maxBeds * 100)
```

**Facility occupancy (line 591):**

```
facilityOccupancy% = round(totalCensus / TOTAL_STAFFED * 100)
```

Where `totalCensus = sum of all unit census values` and `TOTAL_STAFFED = 114`.

---

### 2.6 Aggregate Staffing (lines 534-549)

For each unit with census > 0, looks up the appropriate grid and sums across all three shifts:

```
tRN   = sum of all RN positions across all units and shifts
tLPN  = sum of all LPN positions across all units and shifts
tTech = sum of all Tech positions across all units and shifts
shiftTot = tRN + tLPN + tTech
```

---

### 2.7 Float Coverage (line 602)

```
acuteOpen  = count of acute units where census > 0
floatShift = ceil(acuteOpen / 2)
floatFTE   = floatShift * FTE_MULTIPLIER (1.4)
```

Provides one split-shift float nurse for every two open acute units.

---

### 2.8 Nursing Production FTE (line 603)

```
nursingProd = shiftTot * FTE_MULTIPLIER (1.4)
```

Converts total shift-level staff positions to productive FTE.

---

### 2.9 Role-Level FTE (line 697)

```
rnFTE   = tRN  * 1.4
lpnFTE  = tLPN * 1.4
techFTE = tTech * 1.4
```

---

### 2.10 1:1 Observation FTE (lines 605-606)

```
oneOneProd = observationHoursPerDay * 7 / 40
oneOneAdj  = grossUp(oneOneProd)
```

Converts daily 1:1 observation hours to weekly FTE, then grosses up for NP%.

---

### 2.11 Total Variable FTE (line 608)

**Productive:**

```
totalVarProd = nursingProd + floatFTE + oneOneProd
```

**Adjusted (with NP%):**

```
totalVarAdj = grossUp(nursingProd + floatFTE) + oneOneAdj
```

Note: 1:1 observation is grossed-up separately.

---

### 2.12 NP Hours Added (line 698)

```
varNPadd = totalVarAdj - totalVarProd
```

The additional FTEs required to cover non-productive time.

---

### 2.13 Grand Total FTE (line 610)

**Productive:**

```
grandProd = totalVarProd + fixedFTE
```

**Adjusted:**

```
grandAdj = totalVarAdj + fixedFTE
```

---

### 2.14 EPOB -- Employees Per Occupied Bed (lines 616-617)

**Direct Care (variable only):**

```
dcEpob = totalVarAdj / totalCensus
```

**Total Facility:**

```
totalEpob = grandAdj / totalCensus
```

Returns 0 when census is 0.

---

### 2.15 Patient-to-Staff Ratio (line 686)

```
ratio = census / (RN + LPN + Tech for a given shift)
```

Displayed as e.g. "6:1" (6 patients per staff member).

---

### 2.16 Payroll Period Day Count (line 817)

```
dayCount = max(1, round((maxDate - minDate) / 86400000) + 1)
```

Converts millisecond date range to calendar days, minimum 1.

---

### 2.17 Payroll-Based FTE for Fixed Departments (line 499)

```
fte = (totalHours / dayCount) * 7 / 40
```

Converts actual payroll hours to annualized FTE: daily average hours, scaled to a 7-day week, divided by a 40-hour work week.

---

### 2.18 Actual Non-Productive % from Payroll (line 881)

```
npPct = (npHrs / totalPaidHours) * 100
```

---

### 2.19 Model Daily Hours (line 914)

```
modelDailyHrs = totalStaffPositions * 8
```

Expected hours per day based on census-driven staffing grid (8-hour shifts).

---

### 2.20 Actual Daily Hours from Payroll (line 935)

```
actualDailyHrs = payrollHours / dayCount
```

---

### 2.21 Hours Variance (lines 936-937)

**Absolute:**

```
variance = actualDailyHrs - modelDailyHrs
```

**Percentage:**

```
variancePct = (variance / modelDailyHrs) * 100
```

Positive = overstaffed, negative = understaffed.

---

### 2.22 Actual FTE from Payroll (lines 975-976)

```
actualVarFTE   = ((totalVariablePaidHours - totalVariableNpHours) / dayCount) * 7 / 40
actualFixFTE   = ((totalFixedPaidHours / dayCount) * 7 / 40) + BASELINE_SALARY_FTE
actualTotalFTE = actualVarFTE + actualFixFTE
```

Variable FTE uses **productive** hours only (NP categories — PTO, Sick, Holiday,
Continuing Ed, Education Pay, Jury Duty, Bereavement — are subtracted). Fixed
FTE adds back `BASELINE_SALARY_FTE = 33.625` because salaried rows are filtered
at parse time.

---

### 2.23 EPOB Variance (lines 1320-1323)

```
actDcEpob    = actualVarFTE / totalCensus
actTotalEpob = actualTotalFTE / totalCensus
dcVar        = actDcEpob - dcEpob          (model)
totalVar     = actTotalEpob - totalEpob     (model)
```

Compares actual payroll-derived EPOB against the census-model EPOB.

---

## 3. Quick-Reference Summary Table

| # | Metric | Formula | Typical Use |
|---|---|---|---|
| 1 | **Gross-Up** | `prod / (1 - NP%/100)` | Adjust productive FTE for non-productive time |
| 2 | **Facility Occupancy** | `census / 114 * 100` | Dashboard KPI |
| 3 | **Unit Occupancy** | `census / maxBeds * 100` | Per-unit status |
| 4 | **Nursing Prod FTE** | `shiftPositions * 1.4` | Census-driven staffing cost |
| 5 | **Float FTE** | `ceil(openAcuteUnits / 2) * 1.4` | Float nurse coverage |
| 6 | **1:1 Obs FTE** | `obsHrs * 7 / 40` | Observation staffing |
| 7 | **Total Var Adj FTE** | `grossUp(nursing + float) + grossUp(obs)` | Total variable labor |
| 8 | **Grand Total FTE** | `varAdj + fixedFTE` | Facility-wide labor |
| 9 | **DC EPOB** | `varAdjFTE / census` | Direct care benchmark |
| 10 | **Total EPOB** | `grandAdjFTE / census` | Facility benchmark |
| 11 | **Payroll FTE** | `(hours / days) * 7 / 40` | Actual vs model comparison |
| 12 | **Hours Variance** | `actual - model` | Staffing gap analysis |
| 13 | **Variance %** | `(variance / model) * 100` | Relative over/understaffing |
| 14 | **Patient:Staff** | `census / shiftStaff` | Ratio display |
| 15 | **NP Multiplier** | `1 / (1 - NP%/100)` | Displayed adjustment factor |
