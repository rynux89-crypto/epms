# EPMS Peak Management Operations Checklist

## 1. Purpose

This checklist is for moving the new `Peak management` flow from development into real operation.

It covers:

- DB objects required for `15-minute demand peak`
- SQL Agent job setup
- dashboard validation points
- tenant policy setup
- operational monitoring checks

## 2. Scope

Related files:

- `epms/peak_management.jsp`
- `epms/peak_policy_manage.jsp`
- `docs/sql/create_epms_peak_policy_schema.sql`
- `docs/sql/create_epms_peak_15min_summary.sql`
- `docs/sql/create_peak_15min_summary_agent_job.sql`

## 3. Pre-Deployment Checklist

- Confirm that `dbo.measurements` is collecting `active_power_total` data continuously.
- Confirm that meter timestamps in `dbo.measurements.measured_at` are recorded correctly.
- Confirm that tenant-to-meter mapping exists for operating stores.
- Confirm that SQL Server Agent is enabled in the target environment.
- Confirm that the current database user has permission to create tables, procedures, and Agent jobs.
- Confirm that `epms/peak_management.jsp` and `epms/peak_policy_manage.jsp` are deployed with the latest code.

## 4. DB Deployment Checklist

Run in this order:

1. `docs/sql/create_epms_peak_policy_schema.sql`
2. `docs/sql/create_epms_peak_15min_summary.sql`
3. `docs/sql/create_peak_15min_summary_agent_job.sql`

Validation after execution:

- Confirm that `dbo.peak_policy` exists.
- Confirm that `dbo.peak_15min_summary` exists.
- Confirm that `dbo.sp_refresh_peak_15min_summary` exists.
- Confirm that SQL Agent job `EPMS Peak 15min Summary Refresh` exists.

## 5. Initial Data Refresh Checklist

- Execute `dbo.sp_refresh_peak_15min_summary` once manually after deployment.
- Confirm that `dbo.peak_15min_summary` contains recent rows.
- Confirm that at least one meter has a `bucket_start` value from today.
- Confirm that the latest `refreshed_at` time is recent.

Recommended verification query:

```sql
SELECT TOP 20
    meter_id,
    bucket_start,
    avg_active_power_total,
    refreshed_at
FROM dbo.peak_15min_summary
ORDER BY refreshed_at DESC, bucket_start DESC;
```

## 6. Dashboard Validation Checklist

Open `Peak management` and verify:

- The page loads without SQL or JSP runtime errors.
- `15-minute summary source` is shown correctly.
- If summary table exists, the page shows `15-minute summary table in use`.
- If summary table does not exist, the page falls back to `measurements` calculation.
- `Last summary update time` is displayed when the summary table is used.
- `Summary lag warning` appears only when refresh delay exceeds the expected threshold.
- `Warning targets` and `Control targets` counts are populated.
- `Policy status` table shows store-level threshold usage.
- `Policy view` links preserve filter and return section.

## 7. Peak Policy Setup Checklist

For each managed tenant/store:

- Define `peak limit kW`.
- Define `warning threshold`.
- Define `control threshold`.
- Define `priority`.
- Decide whether `auto control` should be enabled.
- Set valid date range.

Operational rule recommendations:

- Use `warning threshold` below `control threshold`.
- Keep threshold percentages consistent by tenant type.
- Review food, HVAC-heavy, and anchor tenants separately.
- Do not enable automatic control until alert-only operation is stable.

## 8. SQL Agent Job Checklist

Confirm the job schedule:

- Runs every 15 minutes
- Starts automatically with SQL Server Agent
- Has a retry or failure notification policy if used in production

Confirm the job step:

- Executes `EXEC dbo.sp_refresh_peak_15min_summary;`

Confirm the job result:

- Job history shows successful completion.
- `refreshed_at` continues to move forward.
- Dashboard lag warning remains within acceptable range.

## 9. Post-Deployment Monitoring Checklist

Check during the first operating day:

- Peak dashboard values update throughout the day.
- No stores are missing from policy status unexpectedly.
- Repeated exceed ranking looks reasonable.
- Floor/category filters behave correctly.
- Return navigation from policy page works correctly.

Check during the first operating week:

- Summary refresh does not lag repeatedly.
- Warning/control target counts match actual operating conditions.
- Peak limits are not too low or too high for key tenants.
- Repeated exceed stores are reviewed and policy thresholds tuned.

## 10. Failure Response Checklist

If `15-minute summary table` is not being used:

- Verify that `dbo.peak_15min_summary` exists.
- Verify that application DB account can read the table.
- Verify that the page is connected to the intended database.

If `summary lag warning` persists:

- Check SQL Agent job execution history.
- Execute `dbo.sp_refresh_peak_15min_summary` manually.
- Check whether `dbo.measurements` stopped receiving new data.
- Check long-running locks or DB resource issues.

If `policy status` looks empty:

- Verify `dbo.peak_policy` rows exist.
- Verify tenant/store mapping is valid for the current date.
- Verify stores are linked to meters with measurement data.

## 11. Recommended Handover Items

- Share this checklist with operations and facility teams.
- Share policy ownership by store or floor.
- Define who reviews repeated exceed targets daily.
- Define who adjusts `peak_policy` thresholds.
- Define who monitors SQL Agent job failures.

## 12. Done Criteria

Peak management is considered operational when all items below are true:

- `peak_policy` table is created and populated.
- `peak_15min_summary` table is created and refreshing on schedule.
- Dashboard shows summary usage and recent refresh time.
- Warning/control targets are visible and understandable to operators.
- Policy update to dashboard return flow works cleanly.
- Operating team knows how to respond to lag, missing data, and repeated exceed cases.
