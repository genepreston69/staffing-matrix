# Highland Hospital Staffing Matrix - Power BI Template Setup

## Overview

This guide creates a 5-page Power BI report connected to your SharePoint list.
Each page mirrors the staffing matrix application plus adds trend analysis.

**Pages:**
1. **Executive Dashboard** - KPI cards, census gauges, EPOB summary
2. **Shift Staffing** - Unit staffing by shift, patient-to-staff ratios
3. **Position Control** - FTE breakdown (variable vs fixed, productive vs adjusted)
4. **Payroll Variance** - Actual vs model hours, OT, wages
5. **Trends** - All key metrics over time (the real value of Power BI)

---

## Step 1: Connect to SharePoint List

In Power BI Desktop: **Home > Get Data > SharePoint Online List**

Enter your SharePoint site URL (e.g., `https://yourcompany.sharepoint.com/sites/HighlandHospital`)

Select your staffing matrix list, click **Transform Data** to open Power Query.

### Power Query M Code

In Power Query Editor, click **Advanced Editor** and replace with:

```m
let
    Source = SharePoint.Tables("https://YOUR-SHAREPOINT-SITE-URL", [Implementation="2.0", ViewMode="All"]),
    StaffingList = Source{[Title="YOUR-LIST-NAME"]}[Items],

    // Keep only the columns we need (SharePoint adds many system columns)
    #"Removed System Columns" = Table.SelectColumns(StaffingList, List.Select(
        Table.ColumnNames(StaffingList),
        each not Text.StartsWith(_, "_") and not Text.StartsWith(_, "OData")
            and not List.Contains({"ServerRedirectedEmbedUri","ServerRedirectedEmbedUrl",
                "ContentTypeId","ComplianceAssetId","GUID","Attachments","Edit","LinkTitle",
                "LinkTitleNoMenu","Modified","Created","Author","Editor"}, _)
    )),

    // Type the date columns
    #"Typed Dates" = Table.TransformColumnTypes(#"Removed System Columns", {
        {"Timestamp", type datetimezone},
        {"Date", type date},
        {"TimeEntryDate", type date},
        {"PayrollStartDate", type date},
        {"PayrollEndDate", type date}
    }),

    // Sort newest first
    #"Sorted" = Table.Sort(#"Typed Dates", {{"Timestamp", Order.Descending}})
in
    #"Sorted"
```

> **Replace** `YOUR-SHAREPOINT-SITE-URL` and `YOUR-LIST-NAME` with your actual values.

---

## Step 2: Create Unpivoted Helper Tables

The SharePoint list stores data in wide format (one row per push). Power BI visuals
work better with normalized/unpivoted data for unit-level comparisons.

### Table: Census by Unit (New Power Query)

**Home > New Source > Blank Query > Advanced Editor:**

```m
let
    Source = StaffingMatrix,  // Reference to main table
    #"Selected" = Table.SelectColumns(Source, {
        "TimeEntryDate", "Timestamp",
        "Census_1East", "Census_2East", "Census_2West",
        "Census_3East", "Census_3West", "Census_HRC"
    }),
    #"Unpivoted" = Table.UnpivotOtherColumns(#"Selected",
        {"TimeEntryDate", "Timestamp"}, "UnitField", "Census"),
    #"Cleaned Unit" = Table.TransformColumns(#"Unpivoted", {
        {"UnitField", each Text.Replace(_, "Census_", ""), type text}
    }),
    #"Renamed" = Table.RenameColumns(#"Cleaned Unit", {{"UnitField", "Unit"}}),
    #"Add Full Name" = Table.AddColumn(#"Renamed", "UnitName", each
        if [Unit] = "1East" then "1 East - Adult Acute"
        else if [Unit] = "2East" then "2 East - Child Acute"
        else if [Unit] = "2West" then "2 West - Adolescent"
        else if [Unit] = "3East" then "3 East - Adult Acute"
        else if [Unit] = "3West" then "3 West - Adult Acute"
        else if [Unit] = "HRC" then "HRC - SUD/Detox"
        else [Unit], type text),
    #"Add Max Beds" = Table.AddColumn(#"Add Full Name", "MaxBeds", each
        if [Unit] = "1East" then 18
        else if [Unit] = "HRC" then 16
        else 20, Int64.Type)
in
    #"Add Max Beds"
```

### Table: Staffing by Unit and Shift (New Power Query)

```m
let
    Source = StaffingMatrix,
    Units = {"1East", "2East", "2West", "3East", "3West", "HRC"},
    Shifts = {"Day", "Evening", "Night"},
    Roles = {"RN", "LPN", "Tech"},

    // Generate all combinations for each row
    #"Added Custom" = Table.AddColumn(Source, "StaffingRows", each
        let row = _ in
        List.Transform(Units, (u) =>
            List.Transform(Shifts, (s) =>
                List.Transform(Roles, (r) =>
                    [TimeEntryDate = row[TimeEntryDate], Timestamp = row[Timestamp],
                     Unit = u, Shift = s, Role = r,
                     Staff = Record.FieldOrDefault(row, u & "_" & s & "_" & r, 0)]
                )
            )
        )
    ),
    #"Expanded1" = Table.ExpandListColumn(#"Added Custom", "StaffingRows"),
    #"Expanded2" = Table.ExpandListColumn(#"Expanded1", "StaffingRows"),
    #"Expanded3" = Table.ExpandListColumn(#"Expanded2", "StaffingRows"),
    #"ExpandedRecords" = Table.ExpandRecordColumn(#"Expanded3", "StaffingRows",
        {"TimeEntryDate", "Timestamp", "Unit", "Shift", "Role", "Staff"}),
    #"Final" = Table.SelectColumns(#"ExpandedRecords",
        {"TimeEntryDate", "Timestamp", "Unit", "Shift", "Role", "Staff"})
in
    #"Final"
```

### Table: Payroll Variance by Unit (New Power Query)

```m
let
    Source = StaffingMatrix,
    #"Filtered" = Table.SelectRows(Source, each [HasPayrollData] = true),
    Units = {"1East", "2East", "2West", "3East", "3West", "HRC"},

    #"Added Custom" = Table.AddColumn(#"Filtered", "VarianceRows", each
        let row = _ in
        List.Transform(Units, (u) =>
            [TimeEntryDate = row[TimeEntryDate],
             Unit = u,
             Actual_HrsDay = Record.FieldOrDefault(row, "Actual_HrsDay_" & u, 0),
             Model_HrsDay = Record.FieldOrDefault(row, "Model_HrsDay_" & u, 0),
             Variance_HrsDay = Record.FieldOrDefault(row, "Variance_HrsDay_" & u, 0),
             Variance_Pct = Record.FieldOrDefault(row, "Variance_Pct_" & u, 0),
             Actual_HC = Record.FieldOrDefault(row, "Actual_HC_" & u, 0),
             Actual_OT = Record.FieldOrDefault(row, "Actual_OT_" & u, 0),
             Actual_NpHrs = Record.FieldOrDefault(row, "Actual_NpHrs_" & u, 0),
             Actual_Wages = Record.FieldOrDefault(row, "Actual_Wages_" & u, 0)]
        )
    ),
    #"Expanded" = Table.ExpandListColumn(#"Added Custom", "VarianceRows"),
    #"ExpandedRecords" = Table.ExpandRecordColumn(#"Expanded", "VarianceRows",
        {"TimeEntryDate", "Unit", "Actual_HrsDay", "Model_HrsDay", "Variance_HrsDay",
         "Variance_Pct", "Actual_HC", "Actual_OT", "Actual_NpHrs", "Actual_Wages"}),
    #"Final" = Table.SelectColumns(#"ExpandedRecords",
        {"TimeEntryDate", "Unit", "Actual_HrsDay", "Model_HrsDay", "Variance_HrsDay",
         "Variance_Pct", "Actual_HC", "Actual_OT", "Actual_NpHrs", "Actual_Wages"})
in
    #"Final"
```

Click **Close & Apply** when done.

---

## Step 3: DAX Measures

Create a new **Measures Table** (Modeling > New Table > `Measures = {BLANK()}`),
then add these measures:

### KPI Measures

```dax
// Latest record reference
Latest Census = 
    CALCULATE(MAX(StaffingMatrix[TotalCensus]),
        TOPN(1, StaffingMatrix, StaffingMatrix[Timestamp], DESC))

Latest Occupancy = 
    CALCULATE(MAX(StaffingMatrix[OccupancyPct]),
        TOPN(1, StaffingMatrix, StaffingMatrix[Timestamp], DESC))

Latest EPOB DC = 
    CALCULATE(MAX(StaffingMatrix[EPOB_DirectCare]),
        TOPN(1, StaffingMatrix, StaffingMatrix[Timestamp], DESC))

Latest EPOB Total = 
    CALCULATE(MAX(StaffingMatrix[EPOB_TotalFacility]),
        TOPN(1, StaffingMatrix, StaffingMatrix[Timestamp], DESC))

Latest Grand FTE = 
    CALCULATE(MAX(StaffingMatrix[GrandAdjFTE]),
        TOPN(1, StaffingMatrix, StaffingMatrix[Timestamp], DESC))

Total Staffed Beds = 114
```

### Trend Measures

```dax
// Period-over-period change
Census Change = 
    VAR CurrentDate = MAX(StaffingMatrix[TimeEntryDate])
    VAR PrevDate = CALCULATE(MAX(StaffingMatrix[TimeEntryDate]),
        FILTER(ALL(StaffingMatrix), StaffingMatrix[TimeEntryDate] < CurrentDate))
    VAR Current = CALCULATE(MAX(StaffingMatrix[TotalCensus]),
        StaffingMatrix[TimeEntryDate] = CurrentDate)
    VAR Previous = CALCULATE(MAX(StaffingMatrix[TotalCensus]),
        StaffingMatrix[TimeEntryDate] = PrevDate)
    RETURN Current - Previous

EPOB DC Change = 
    VAR CurrentDate = MAX(StaffingMatrix[TimeEntryDate])
    VAR PrevDate = CALCULATE(MAX(StaffingMatrix[TimeEntryDate]),
        FILTER(ALL(StaffingMatrix), StaffingMatrix[TimeEntryDate] < CurrentDate))
    VAR Current = CALCULATE(MAX(StaffingMatrix[EPOB_DirectCare]),
        StaffingMatrix[TimeEntryDate] = CurrentDate)
    VAR Previous = CALCULATE(MAX(StaffingMatrix[EPOB_DirectCare]),
        StaffingMatrix[TimeEntryDate] = PrevDate)
    RETURN Current - Previous

OT Total = 
    CALCULATE(MAX(StaffingMatrix[Actual_OT_Total]),
        TOPN(1, StaffingMatrix, StaffingMatrix[Timestamp], DESC))
```

### Variance Measures

```dax
Variance Color = 
    IF(SUM('PayrollVariance'[Variance_HrsDay]) > 0, "#dc3545", "#28a745")

Total Actual Hrs = SUM('PayrollVariance'[Actual_HrsDay])
Total Model Hrs = SUM('PayrollVariance'[Model_HrsDay])
Total Variance Hrs = SUM('PayrollVariance'[Variance_HrsDay])
Total Variance Pct = DIVIDE(SUM('PayrollVariance'[Variance_HrsDay]),
    SUM('PayrollVariance'[Model_HrsDay]), 0) * 100
Total OT Hrs = SUM('PayrollVariance'[Actual_OT])
Total Wages = SUM('PayrollVariance'[Actual_Wages])
```

### Gauge Thresholds

```dax
EPOB Target = 1.0
EPOB Warning = 1.2
Occupancy Target = 85
```

---

## Step 4: Report Pages

### Page 1: Executive Dashboard

**Theme:** Use dark navy (#1b2a4a) header bar with teal (#008080) accents.

| Visual | Data | Position |
|--------|------|----------|
| **Card** - Total Census | `[Latest Census]` | Top row, 1st |
| **Card** - Occupancy % | `[Latest Occupancy]` with % format | Top row, 2nd |
| **Card** - DC EPOB | `[Latest EPOB DC]` | Top row, 3rd |
| **Card** - Total FTE | `[Latest Grand FTE]` | Top row, 4th |
| **Gauge** - Occupancy | Value: `OccupancyPct`, Max: 100, Target: 85 | Middle left |
| **Gauge** - EPOB DC | Value: `EPOB_DirectCare`, Max: 2.5, Target: 1.0 | Middle right |
| **Clustered Bar** - Census by Unit | Axis: `Unit`, Value: `Census` from CensusByUnit table | Bottom left |
| **Donut** - FTE Split | Values: `VarAdjFTE`, `FixedFTE` | Bottom right |
| **Table** - Latest Snapshot | Key fields from most recent push | Bottom |

**Conditional Formatting:**
- EPOB card: Green if < 1.0, Yellow 1.0-1.2, Red > 1.2
- Variance cards: Green if negative (under budget), Red if positive

---

### Page 2: Shift Staffing Requirements

| Visual | Data |
|--------|------|
| **Stacked Bar** - Staff by Unit & Shift | Axis: `Unit`, Legend: `Shift`, Value: `Staff` from StaffingByUnit |
| **Stacked Bar** - Staff by Unit & Role | Axis: `Unit`, Legend: `Role`, Value: `Staff` from StaffingByUnit |
| **Matrix** - Full Staffing Grid | Rows: `Unit`, Columns: `Shift` + `Role`, Values: `Staff` |
| **Card** - Total RN | `Total_RN` | Top row |
| **Card** - Total LPN | `Total_LPN` | Top row |
| **Card** - Total Tech | `Total_Tech` | Top row |
| **Card** - Float Positions | `FloatShiftPositions` | Top row |
| **Table** - Patient:Staff Ratios | Columns: Unit, Day Ratio, Eve Ratio, Night Ratio |

---

### Page 3: Position Control

| Visual | Data |
|--------|------|
| **Stacked Bar** - FTE by Role | Categories: RN/LPN/Tech/Float/1:1, Values: ProdFTE + NP Add |
| **Waterfall** - FTE Build-up | Start: `VarProdFTE` > NP Add > `FixedFTE` = `GrandAdjFTE` |
| **Cards** - Grand Productive FTE, Grand Adjusted FTE, NP Add, Fixed FTE | Top row |
| **Table** - Variable Detail | RN/LPN/Tech/Float/1:1 rows with Productive, Adjusted, NP Add columns |
| **Donut** - Fixed by Category | Slice by Clinical Ops / Support / Admin |
| **KPI** - EPOB Productive | Value: `EPOB_Productive`, Target: 1.0 |

---

### Page 4: Payroll Variance

**Slicer:** `TimeEntryDate` dropdown at top

| Visual | Data |
|--------|------|
| **Clustered Bar** - Actual vs Model Hrs/Day | Axis: `Unit`, Values: `Actual_HrsDay`, `Model_HrsDay` |
| **Bar** - Variance % by Unit | Axis: `Unit`, Value: `Variance_Pct` (conditional: red >0, green <0) |
| **Cards** - Total Actual Hrs, Total Model Hrs, Total Variance %, Total OT | Top row |
| **Stacked Bar** - OT by Unit | Axis: `Unit`, Value: `Actual_OT` |
| **Table** - Full Variance Detail | Unit, Actual Hrs, Model Hrs, Variance, Variance %, HC, OT, Wages |
| **KPI** - Actual vs Model EPOB | Value: `Actual_EPOB_DC`, Target: `EPOB_DirectCare` |

---

### Page 5: Trends Over Time

**Slicer:** Date range slicer for `TimeEntryDate`

| Visual | Data |
|--------|------|
| **Line Chart** - Census Trend | X: `TimeEntryDate`, Y: `TotalCensus` + per-unit census lines |
| **Line Chart** - FTE Trend | X: `TimeEntryDate`, Y: `GrandAdjFTE`, `VarAdjFTE`, `FixedFTE` |
| **Line Chart** - EPOB Trend | X: `TimeEntryDate`, Y: `EPOB_DirectCare`, `EPOB_TotalFacility`, with target reference line at 1.0 |
| **Line Chart** - Variance Trend | X: `TimeEntryDate`, Y: `Variance_VarHrsDay_Total` |
| **Area Chart** - OT Trend | X: `TimeEntryDate`, Y: `Actual_OT_Total` |
| **Line Chart** - Occupancy Trend | X: `TimeEntryDate`, Y: `OccupancyPct` with target line at 85% |
| **Small Multiples** - Unit Census | Grid of sparklines, one per unit |

---

## Step 5: Formatting & Theme

### Color Palette (matches the web app)

```json
{
    "name": "Highland Hospital",
    "dataColors": [
        "#008080", "#1b2a4a", "#28a745", "#dc3545",
        "#ffc107", "#6c757d", "#17a2b8", "#e9ecef"
    ],
    "background": "#FFFFFF",
    "foreground": "#1b2a4a",
    "tableAccent": "#008080"
}
```

Save as `highland-theme.json`, then in Power BI: **View > Themes > Browse for themes**.

### Number Formats
- Census: whole numbers, no decimals
- FTE: 1 decimal place (0.0)
- EPOB: 2 decimal places (0.00)
- Percentages: 1 decimal + % symbol
- Wages: currency, 2 decimals
- Hours: 1 decimal

### Conditional Formatting Rules
| Metric | Green | Yellow | Red |
|--------|-------|--------|-----|
| Variance % | < 0% | 0-5% | > 5% |
| EPOB DC | < 1.0 | 1.0-1.2 | > 1.2 |
| Occupancy | 80-90% | 70-80% | < 70% or > 95% |
| OT Hours | < 20 | 20-50 | > 50 |

---

## Step 6: Auto-Refresh

1. **Publish** to Power BI Service (Workspace)
2. Go to **Dataset Settings > Scheduled Refresh**
3. Configure credentials for your SharePoint connection
4. Set refresh schedule (recommended: every 30 minutes during business hours)

This ensures dashboards stay current as the staffing matrix app pushes new data.

---

## Quick Start Checklist

- [ ] Connect to SharePoint list (Step 1)
- [ ] Create CensusByUnit helper table (Step 2)
- [ ] Create StaffingByUnit helper table (Step 2)
- [ ] Create PayrollVariance helper table (Step 2)
- [ ] Add DAX measures (Step 3)
- [ ] Build Executive Dashboard page (Step 4)
- [ ] Build Shift Staffing page (Step 4)
- [ ] Build Position Control page (Step 4)
- [ ] Build Payroll Variance page (Step 4)
- [ ] Build Trends page (Step 4)
- [ ] Apply theme and formatting (Step 5)
- [ ] Publish and configure auto-refresh (Step 6)
