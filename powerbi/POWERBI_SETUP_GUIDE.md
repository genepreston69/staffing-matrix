# Highland Staffing Matrix — Power BI Build Guide

Build a complete Power BI report in ~15 minutes using the ready-made queries and measures in the `queries/` folder.

## Prerequisites

- **Power BI Desktop** (any recent version)
- Access to the SharePoint site containing the **StaffingMatrix** list
- Microsoft 365 account with SharePoint read permissions

---

## Step 1: Create a New Report

1. Open **Power BI Desktop**
2. Click **File > New** (start with a blank report)
3. **Save immediately** as `Highland_Staffing_Matrix.pbix`

---

## Step 2: Create the SharePoint Parameter

1. Go to **Home > Transform data** (opens Power Query Editor)
2. Click **Home > Manage Parameters > New Parameter**
3. Configure:
   - **Name:** `SharePointSiteURL`
   - **Type:** Text
   - **Current Value:** Your SharePoint site URL (e.g. `https://yourorg.sharepoint.com/sites/HighlandHospital`)
4. Click **OK**

---

## Step 3: Add the StaffingData Query

1. In Power Query Editor, click **Home > New Source > Blank Query**
2. Click **Home > Advanced Editor**
3. Delete everything in the editor
4. Open `queries/03_StaffingData.m` and **copy/paste the entire contents** (skip the comment lines at the top)
5. Click **Done**
6. In the right pane, rename the query to `StaffingData`
7. When prompted, authenticate with your **Organizational account**
8. The preview should show your SharePoint list data with all 208 columns plus the DateKey column

---

## Step 4: Add the Units Query

1. Click **Home > New Source > Blank Query**
2. Click **Home > Advanced Editor**
3. Open `queries/02_Units.m` and **copy/paste the contents** (skip comments)
4. Click **Done**
5. Rename the query to `Units`
6. You should see 6 rows (one per nursing unit)

---

## Step 5: Close & Apply

1. Click **Home > Close & Apply**
2. Wait for the data to load from SharePoint

---

## Step 6: Create the Date Table

1. In the main Power BI Desktop view, click **Modeling > New Table**
2. Open `queries/04_DateTable.dax`
3. **Copy/paste the DAX formula** (everything after the comment block, starting with `DateTable =`)
4. Press **Enter** — the DateTable will be created with ~1,096 rows (2025-2027)
5. Select the DateTable in the Fields pane
6. Click **Table Tools > Mark as Date Table**
7. Select the **Date** column and click **OK**

---

## Step 7: Create the Relationship

1. Go to **Model view** (left sidebar, the diagram icon)
2. **Drag** `DateTable[Date]` onto `StaffingData[DateKey]`
3. This creates a one-to-many relationship (DateTable → StaffingData)
4. Double-click the relationship line to verify:
   - **From:** DateTable > Date
   - **To:** StaffingData > DateKey
   - **Cardinality:** One to many
   - **Cross filter direction:** Both
5. Click **OK**

---

## Step 8: Add All DAX Measures

Open `queries/05_DAX_Measures.dax` and create each measure:

1. In **Report view**, select the **StaffingData** table in the Fields pane
2. Click **Modeling > New Measure**
3. Paste the first measure formula (e.g. `Total Census = SUM(StaffingData[TotalCensus])`)
4. Press **Enter**
5. Repeat for each measure in the file

**There are 65 measures organized in 7 folders:**

| Folder | Count | Key Measures |
|--------|-------|-------------|
| Core Metrics | 10 | Total Census, Occupancy %, DC EPOB, Total EPOB |
| Census by Unit | 6 | Census per unit (1East, 2East, 2West, 3East, 3West, HRC) |
| FTE | 6 | Variable FTE, Fixed FTE, Grand Total FTE, by role |
| Payroll Variance | 11 | Hours Variance, OT Hours, Actual vs Model EPOB |
| MTD Metrics | 16 | MTD Avg Daily Census (facility + 6 units), MTD EPOB, MTD FTE |
| YTD Metrics | 16 | YTD Avg Daily Census (facility + 6 units), YTD EPOB, YTD FTE |
| Comparisons | 4 | Prior Month Avg Census, MTD vs Prior Month, FTE Variance |

**To set Display Folders:** Select a measure > Properties pane > Display Folder > type the folder name.

**TIP:** You can create measures faster by staying in the formula bar — after pressing Enter on one measure, immediately click New Measure for the next one.

---

## Step 9: Build Report Pages

### Page 1: Executive Dashboard

1. Rename the default page to **Executive Dashboard**
2. Add a **Date Slicer:** Drag `DateTable[Date]` onto the canvas, change visual type to Slicer, set to "Between"
3. Add **KPI Cards** (Insert > Card visual for each):
   - Total Census, Occupancy %, DC EPOB, Total EPOB, Variable FTE, Grand Total FTE
4. Add a second row of cards for MTD/YTD:
   - MTD Avg Daily Census, MTD Avg Occupancy %, MTD Avg DC EPOB
   - YTD Avg Daily Census, YTD Avg Occupancy %, YTD Avg DC EPOB
5. Add a **Line Chart:** Axis = `DateTable[Date]`, Values = `Total Census` + `MTD Avg Daily Census`
6. Add a **Line Chart:** Axis = `DateTable[Date]`, Values = `DC EPOB` + `Total EPOB`

### Page 2: Shift Staffing

1. Add new page, rename to **Shift Staffing**
2. Add Date Slicer
3. Add a **Table** visual with columns:
   - `Date`, `Census_1East`, `1East_Day_RN`, `1East_Day_LPN`, `1East_Day_Tech`, `1East_Evening_RN`, etc.
   - Repeat for all units, end with `Total_ShiftStaff`
4. Add a second **Table** for Patient-to-Staff Ratios:
   - `Date`, all `*_Ratio_Day`, `*_Ratio_Eve`, `*_Ratio_Night` columns

### Page 3: Position Control

1. Add new page, rename to **Position Control**
2. Add Date Slicer
3. Add a **Table** with: `Date`, `RN_ProdFTE`, `RN_AdjFTE`, `LPN_ProdFTE`, `LPN_AdjFTE`, `Tech_ProdFTE`, `Tech_AdjFTE`, `Float_ProdFTE`, `Float_AdjFTE`, `OneOne_ProdFTE`, `OneOne_AdjFTE`, `VarProdFTE`, `VarAdjFTE`, `VarNP_Add`, `FixedFTE`, `GrandAdjFTE`
4. Add **Cards** for Variable FTE, Fixed FTE, Grand Total FTE
5. Add a **Clustered Bar Chart:** Axis = `DateTable[YearMonth]`, Values = RN/LPN/Tech Adj FTE measures

### Page 4: Payroll Variance

1. Add new page, rename to **Payroll Variance**
2. Add Date Slicer
3. Add **Cards:** Hours Variance, Variance %, Actual Daily Hours, Model Daily Hours, OT Hours, EPOB DC Variance
4. Add a **Table** with all `Model_HrsDay_*`, `Actual_HrsDay_*`, `Variance_HrsDay_*`, `Variance_Pct_*` columns
5. Add a **Clustered Bar Chart:** Axis = `DateTable[YearMonth]`, Values = Actual Daily Hours + Model Daily Hours

### Page 5: Trends

1. Add new page, rename to **Trends**
2. Add Date Slicer
3. Add **Line Charts:**
   - Census Over Time: Axis = Date, Values = Total Census
   - Occupancy Over Time: Axis = Date, Values = Occupancy %
   - EPOB Trend: Axis = Date, Values = DC EPOB, Total EPOB, Actual DC EPOB, Actual Total EPOB
   - FTE Trend: Axis = Date, Values = Variable FTE, Fixed FTE, Grand Total FTE

### Page 6: MTD / YTD Analytics (NEW)

1. Add new page, rename to **MTD / YTD Analytics**
2. **MTD Section** — Add Cards:
   - MTD Avg Daily Census, MTD Avg Occupancy %, MTD Avg DC EPOB, MTD Total OT Hours, MTD Avg Grand FTE, MTD Days Count
3. **MTD Census by Unit** — Add Cards:
   - MTD Avg Census 1East, 2East, 2West, 3East, 3West, HRC
4. **Comparisons** — Add Cards:
   - Census MTD vs Prior Month, Census MTD vs Prior Month %
5. **YTD Section** — Add Cards:
   - YTD Avg Daily Census, YTD Avg Occupancy %, YTD Avg DC EPOB, YTD Total OT Hours, YTD Avg Grand FTE, YTD Days Count
6. **YTD Census by Unit** — Add Cards:
   - YTD Avg Census 1East, 2East, 2West, 3East, 3West, HRC

---

## Step 10: Apply Theme (Optional)

For the Highland navy/teal look:
1. Go to **View > Themes > Customize current theme**
2. Set:
   - **Primary color:** #1B2A4A (navy)
   - **Secondary color:** #2E8B8B (teal)
   - **Background:** #FFFFFF
3. Click **Apply**

---

## Step 11: Save & Publish

1. **Save** the .pbix file
2. To publish: **Home > Publish** > select your Power BI workspace
3. In Power BI Service, set up **Scheduled Refresh** (daily recommended)

---

## File Reference

| File | Purpose |
|------|---------|
| `queries/01_SharePointSiteURL_Parameter.m` | SharePoint site URL parameter |
| `queries/02_Units.m` | Static unit lookup table (6 rows) |
| `queries/03_StaffingData.m` | SharePoint list connection (208 columns + DateKey) |
| `queries/04_DateTable.dax` | Calendar table (2025-2027) |
| `queries/05_DAX_Measures.dax` | All 65 DAX measures (Core + MTD + YTD + Comparisons) |

---

## MTD / YTD Measure Logic

All MTD and YTD measures use **AVERAGE** (not SUM) to compute the Average Daily Census:

```
MTD Avg Daily Census =
    Average of TotalCensus for all days
    from 1st of current month through today
```

This means:
- **MTD Avg Daily Census** = Sum of daily census values in current month / number of days with data
- **YTD Avg Daily Census** = Sum of daily census values in current year / number of days with data
- All derived metrics (Occupancy %, EPOB, FTE) use the same MTD/YTD averaging pattern
- These measures are **independent of the date slicer** — they always show current-period averages

---

## Data Flow

```
Staffing Matrix App (browser)
        │  Push via Power Automate webhook
        ▼
SharePoint List ("StaffingMatrix")
        │  Power Query connector
        ▼
Power BI Desktop (.pbix)
        │  65 DAX measures
        ▼
6 Report Pages
```
