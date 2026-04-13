# SharePoint Push Flow — Upsert by `TimeEntryDate`

## Why this change

Every click of **Push to SharePoint** in the Staffing Matrix app POSTs the day's payload to the Power Automate webhook, and the flow today calls **Create item** unconditionally. That means pushing the same `TimeEntryDate` twice (e.g., after correcting a census, uploading payroll late, or re-running a day) creates a second row in the SharePoint list, then a third, and so on. Over time the list — and the Pull Trends chart that reads from it — fills with duplicate records for the same date.

This guide walks through editing the existing push flow so the **last push for any given `TimeEntryDate` becomes the source of truth**: if a row for that date already exists, update it; otherwise create a new one.

No app code changes are required. The payload already includes `TimeEntryDate` (see `index.html:2034`), so the flow has everything it needs to look up the existing row.

---

## Step 1 — Find the internal column name for `TimeEntryDate`

The SharePoint connector's Filter Query uses the column's **internal** name, which is frozen at creation time and often differs from the display name. If the column was ever renamed, SharePoint typically keeps the original internal name and may append `0` (e.g., `TimeEntryDate0`). The app's field map in `index.html:2611` already suggests the internal name is `TimeEntryDate0`, but confirm before editing the flow.

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

Write the internal name down. You'll paste it into one place below. The rest of this guide uses the placeholder `<INTERNAL_COLUMN_NAME>`.

---

## Step 2 — Edit the push flow

Open the existing flow in the Power Automate portal. It currently has one SharePoint action: **Create item**. You will add two actions in front of it and wrap the Create item in a Condition.

### 2a. Insert `Get items` before `Create item`

1. Click the `+` between the HTTP trigger and `Create item` → **Add an action** → SharePoint → **Get items**.
2. Configure:
   - **Site Address**: same site as the existing Create item.
   - **List Name**: same list as the existing Create item.
   - **Filter Query** (expand advanced options):
     ```
     <INTERNAL_COLUMN_NAME> eq '@{triggerBody()?['TimeEntryDate']}'
     ```
     Replace `<INTERNAL_COLUMN_NAME>` with the value you confirmed in Step 1. Keep the single quotes around the trigger expression — `TimeEntryDate` is a string.
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

If step 1 or 2 fails with a Filter Query error in the flow run, the most common cause is the wrong internal column name — re-check Step 1.

---

## Rollback

If you need to revert to the previous behavior:
1. Drag the `Create item` action out of the **If no** branch and back above the Condition.
2. Delete the Condition and the `Get items` action.
3. Save. The flow is back to blind-create mode.

Keep in mind this will re-introduce duplicates on repeat pushes, so only roll back while diagnosing.
