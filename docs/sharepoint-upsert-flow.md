# SharePoint Push Flow — Upsert by `TimeEntryDate`

## Why this change

Every click of **Push to SharePoint** in the Staffing Matrix app POSTs the day's payload to the Power Automate webhook, and the flow today calls **Create item** unconditionally. That means pushing the same `TimeEntryDate` twice (e.g., after correcting a census, uploading payroll late, or re-running a day) creates a second row in the SharePoint list, then a third, and so on. Over time the list — and the Pull Trends chart that reads from it — fills with duplicate records for the same date.

This guide walks through editing the existing push flow so the **last push for any given `TimeEntryDate` becomes the source of truth**: if a row for that date already exists, update it; otherwise create a new one.

No app code changes are required. The payload already includes `TimeEntryDate` (see `index.html:2034`), so the flow has everything it needs to look up the existing row.

---

## Step 1 — Confirm the column type and internal name

`TimeEntryDate` in the SharePoint list is a **Date and time** column (Include Time = No). That matters because SharePoint's OData filter syntax for date columns is different from text columns — equality on a bare date string is unreliable, so this guide uses a **day-range filter** instead (see Step 2a).

You also need the column's **internal** name, which is frozen at creation and can differ from the display name. The app's field map in `index.html:2611` indicates the internal name is **`TimeEntryDate0`** (SharePoint appended `0` because the original name was reserved). Verify once before editing the flow.

Two ways to confirm:

**A. From SharePoint list settings**
1. Open the SharePoint list in a browser.
2. Click the gear icon → **List settings**.
3. Scroll to the **Columns** table and click the `TimeEntryDate` column.
4. In the browser address bar, find the `&Field=...` query parameter. The value after `Field=` is the internal name.

**B. From the existing flow**
1. Open the flow in Power Automate.
2. Click the existing **Create item** action and expand the advanced parameters.
3. Find the field whose value is `TimeEntryDate` from the HTTP trigger body. The label shown by the connector is the display name; hover/expand to see the internal name, or compare to step A.

The rest of this guide uses `TimeEntryDate0` as the internal name. If yours differs, replace it everywhere below.

---

## Step 2 — Edit the push flow

Open the existing flow in the Power Automate portal. It currently has one SharePoint action: **Create item**. You will add two actions in front of it and wrap the Create item in a Condition.

### 2a. Insert `Get items` before `Create item`

1. Click the `+` between the HTTP trigger and `Create item` → **Add an action** → SharePoint → **Get items**.
2. Configure:
   - **Site Address**: same site as the existing Create item.
   - **List Name**: same list as the existing Create item.
   - **Filter Query** (expand advanced options) — paste this **single line** (do not break it across lines):
     ```
     TimeEntryDate0 ge '@{triggerBody()?['TimeEntryDate']}' and TimeEntryDate0 lt '@{addDays(triggerBody()?['TimeEntryDate'], 1, 'yyyy-MM-dd')}'
     ```
     Why a range and not `eq`: `TimeEntryDate0` is a Date column. SharePoint stores it as a datetime under the hood, so an `eq` against a bare date string is unreliable across timezones. The range `[date, date+1)` matches exactly the rows whose date equals the payload's `TimeEntryDate`.

     The app sends `TimeEntryDate` as `YYYY-MM-DD` (see `index.html:2034`), which plugs straight into both expressions. If your internal column name differs from `TimeEntryDate0`, replace both occurrences.
   - **Top Count**: `1`. We only need to know whether at least one row exists.

### 2b. Wrap `Create item` in a Condition

1. Below the new `Get items`, add a **Condition** action.
2. In the left operand, switch to **Expression** and paste:
   ```
   length(outputs('Get_items')?['body/value'])
   ```
   (If you renamed the Get items action, change `Get_items` to the actual action name — Power Automate replaces spaces with underscores.)
3. Operator: **is greater than**.
4. Right operand: `0`.

### 2c. `If yes` branch — Update item

1. Inside **If yes**, add **SharePoint → Update item**.
2. Configure:
   - **Site Address** and **List Name**: same list.
   - **Id**: switch to Expression and paste:
     ```
     first(outputs('Get_items')?['body/value'])?['ID']
     ```
   - **Every other field**: copy the mapping from the existing Create item action exactly. If you leave any column blank in Update item, SharePoint will clear that column on update. The easiest way: open the Create item action in a second browser tab and copy the dynamic-content expression from each field into the matching field of Update item.

### 2d. `If no` branch — existing Create item

1. **Drag** the original `Create item` action from outside the Condition into the **If no** branch. Do **not** recreate it — this preserves all 200+ column mappings.
2. Delete the original (now-empty) Create item position outside the Condition if one remains.

### 2e. Save and test

1. Click **Save**.
2. Click **Test** → **Manually** → **Save & Test**, then trigger a push from the app.
3. Open the flow run details and confirm the run entered either the **If yes** (Update) branch or the **If no** (Create) branch — never both.

---

## Step 3 — Verify end-to-end

Run this checklist after the flow saves cleanly.

1. In the app, pick today's `TimeEntryDate` (e.g., **2026-04-13**). Enter census and click **Push to SharePoint**. Open the SharePoint list, filter `TimeEntryDate = 2026-04-13`: expect exactly **one** row, with current `Timestamp`.
2. Change any census or observation value. Click **Push to SharePoint** again for the same date. Re-check the list: still exactly **one** row, values reflect the second push, `Timestamp` is newer.
3. Change to a different `TimeEntryDate` you've never pushed before. Push. Expect a **second** row in the list — proves the Create branch still fires for new dates.
4. Click **Pull from SharePoint** (Trends) in the app. Confirm no duplicate dates appear in the chart.
5. Open the flow's **Run history**. For each test run, expand it and verify the correct branch (Update vs. Create) executed.

If step 1 or 2 fails with a Filter Query error in the flow run, expand the failing **Get items** action in the run details and look at the response body:

- `Column 'X' does not exist` — wrong internal column name. Re-check Step 1.
- `The expression … is not valid` — most often a quoting issue. Confirm the Filter Query is on a single line and that `@{…}` is wrapped in single quotes inside the expression (`'@{triggerBody()?['TimeEntryDate']}'`).
- The Get items returns `0` results when you know a duplicate exists — the column is likely storing values with a non-midnight time (Include Time was once enabled, then disabled). Open one of the existing rows in SharePoint, hover the date, and check whether it has a time component. If so, the day-range filter still works; the `eq` form would not.

---

## Rollback

If you need to revert to the previous behavior:
1. Drag the `Create item` action out of the **If no** branch and back above the Condition.
2. Delete the Condition and the `Get items` action.
3. Save. The flow is back to blind-create mode.

Keep in mind this will re-introduce duplicates on repeat pushes, so only roll back while diagnosing.
