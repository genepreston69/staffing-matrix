# Highland Staffing Matrix — Power BI Setup Guide

## Prerequisites

- **Power BI Desktop** version May 2023 or later (for PBIP format support)
- Access to the SharePoint Online site containing the **StaffingMatrix** list
- Microsoft 365 organizational account with SharePoint read permissions

---

## Step 1: Enable PBIP Preview Feature

Power BI Desktop must have the PBIP format enabled:

1. Open **Power BI Desktop**
2. Go to **File > Options and settings > Options**
3. Select **Preview features** in the left pane
4. Check **Power BI Project (.pbip) save option**
5. Click **OK** and restart Power BI Desktop

---

## Step 2: Open the Project

1. In Power BI Desktop, go to **File > Open report**
2. Navigate to the `powerbi/` folder in this repository
3. Select **Highland_Staffing_Matrix.pbip**
4. The project will load with 3 tables (DateTable, Units, StaffingData) and 6 report pages

---

## Step 3: Configure the SharePoint Connection

The data source points to a placeholder URL that must be updated:

1. Go to **Home > Transform data** (opens Power Query Editor)
2. In the left **Queries** pane, click on **SharePointSiteURL**
3. Replace the value `https://YOUR_TENANT.sharepoint.com/sites/YOUR_SITE` with your actual SharePoint site URL
   - Example: `https://contoso.sharepoint.com/sites/HighlandHospital`
4. Click **Close & Apply**

### SharePoint List Requirements

The connection expects a SharePoint list named **StaffingMatrix** with columns matching the ~208 fields defined in `powerautomate-trigger-schema.json`. This list is automatically populated by the Power Automate flow from the staffing matrix application.

---

## Step 4: Authenticate

When prompted:
1. Select **Organizational account**
2. Sign in with your Microsoft 365 credentials
3. Click **Connect**

If you encounter permission errors, verify you have at least **Read** access to the SharePoint site and list.

---

## Step 5: Refresh Data

1. Click **Home > Refresh** to load data from SharePoint
2. The StaffingData table will populate with all historical daily records
3. The DateTable (2025-2027) generates automatically via DAX
4. The Units table is a static lookup (6 nursing units)

---

## Step 6: Explore the Report

### Report Pages

| Page | Description |
|------|-------------|
| **Executive Dashboard** | KPI cards (Census, Occupancy, EPOB, FTE), MTD/YTD summary cards, census trend line, EPOB trend |
| **Shift Staffing** | Census-driven staffing by unit/shift/role (RN, LPN, Tech), patient-to-staff ratios |
| **Position Control** | FTE breakdown by role (Productive vs Adjusted), Fixed vs Variable, NP additions |
| **Payroll Variance** | Actual vs Model hours comparison, variance by unit, OT hours, EPOB variance |
| **Trends** | Historical line charts for Census, Occupancy, EPOB, FTE over time |
| **MTD / YTD Analytics** | **NEW** — Average Daily Census metrics for month-to-date and year-to-date periods |

### Using Date Slicers

Every page has a date slicer. For the core metrics pages (Shift Staffing, Position Control, Payroll Variance), select a single date to see that day's snapshot. For Trends, select a date range to see movement over time.

**Note:** MTD and YTD measures on the "MTD / YTD Analytics" page always calculate relative to TODAY(), regardless of the date slicer — they show rolling period averages.

---

## DAX Measure Reference

### Measure Folders

| Folder | Measures | Description |
|--------|----------|-------------|
| **Core Metrics** | Total Census, Occupancy %, Total RN/LPN/Tech, DC EPOB, Total EPOB, NP %, Obs Hours | Daily snapshot metrics |
| **Census by Unit** | Census 1East, 2East, 2West, 3East, 3West, HRC | Per-unit census |
| **FTE** | Variable FTE, Fixed FTE, Grand Total FTE, RN/LPN/Tech Adj FTE | FTE calculations |
| **Payroll Variance** | Hours Variance, Variance %, Actual/Model Daily Hours, OT Hours, Actual EPOB | Payroll comparison |
| **MTD Metrics** | MTD Avg Daily Census (facility + 6 units), MTD Avg Occupancy %, MTD Avg DC/Total EPOB, MTD Avg Variable/Grand FTE, MTD Total OT Hours, MTD Avg Hours Variance, MTD Days Count | Month-to-date averages based on Average Daily Census |
| **YTD Metrics** | YTD Avg Daily Census (facility + 6 units), YTD Avg Occupancy %, YTD Avg DC/Total EPOB, YTD Avg Variable/Grand FTE, YTD Total OT Hours, YTD Avg Hours Variance, YTD Days Count | Year-to-date averages based on Average Daily Census |
| **Comparisons** | Prior Month Avg Census, Census MTD vs Prior Month, Census MTD vs Prior Month %, Actual vs Model FTE Variance | Period-over-period comparisons |

### Key MTD/YTD Formulas

**MTD Average Daily Census:**
```dax
VAR _today = TODAY()
VAR _monthStart = DATE(YEAR(_today), MONTH(_today), 1)
RETURN CALCULATE(
    AVERAGE(StaffingData[TotalCensus]),
    DateTable[Date] >= _monthStart && DateTable[Date] <= _today,
    ALL(DateTable)
)
```

**YTD Average Daily Census:**
```dax
VAR _today = TODAY()
VAR _yearStart = DATE(YEAR(_today), 1, 1)
RETURN CALCULATE(
    AVERAGE(StaffingData[TotalCensus]),
    DateTable[Date] >= _yearStart && DateTable[Date] <= _today,
    ALL(DateTable)
)
```

These same patterns are applied across all unit-level census, EPOB, FTE, and variance metrics.

---

## Step 7: Publish to Power BI Service (Optional)

1. Click **Home > Publish**
2. Select your Power BI workspace
3. The report and dataset will be published
4. In the Power BI Service, configure **Scheduled Refresh** to keep the SharePoint data current:
   - Go to **Dataset settings > Scheduled refresh**
   - Set to refresh daily (recommended: early morning after the previous day's data is pushed)
   - Configure SharePoint credentials under **Data source credentials**

---

## Step 8: Save as .pbix (Optional)

If you prefer the traditional .pbix format:
1. With the PBIP project open, go to **File > Save as**
2. Change the file type to **Power BI files (.pbix)**
3. Save to your desired location

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| "Cannot find SharePoint list" | Verify the list is named exactly **StaffingMatrix** (case-sensitive) |
| "Access denied" | Ensure your M365 account has Read access to the SharePoint site |
| MTD/YTD measures show BLANK | No data exists in StaffingData for the current month/year yet — push census data from the app |
| Date slicer empty | Click Refresh to load data; ensure the SharePoint list has records |
| PBIP won't open | Enable the PBIP preview feature (Step 1) and restart Power BI Desktop |

---

## Data Flow Architecture

```
Staffing Matrix App (browser)
        │
        │  Push via Power Automate webhook
        ▼
SharePoint Online List ("StaffingMatrix")
        │
        │  Power Query / SharePoint connector
        ▼
Power BI Semantic Model (StaffingData table)
        │
        │  DAX measures (Core + MTD + YTD)
        ▼
Power BI Report (6 pages)
```
