# Aggregate Job Operations

## Standard

- Preferred standard for new DB servers: `SQL Server Agent`
- Fallback for environments without SQL Agent: `Windows Task Scheduler`

## Current Server

- `SQL Server Agent (MSSQLSERVER)` is currently `Stopped`
- Therefore the current server continues to use:
  - `EPMS Aggregate Hourly`
  - `EPMS Aggregate Rollup`

## New Server Migration Standard

Use SQL Agent on the new DB server if the service is available.

### 1. Create aggregate procedures and views

Run:

- [create_epms_schema.sql](/c:/Tomcat%209.0/webapps/ROOT/docs/sql/create_epms_schema.sql)
- or [update_aggregate_measurements_schema.sql](/c:/Tomcat%209.0/webapps/ROOT/docs/sql/update_aggregate_measurements_schema.sql)

### 2. Create SQL Agent jobs

Run in SSMS against `msdb`:

- [create_aggregate_agent_jobs.sql](/c:/Tomcat%209.0/webapps/ROOT/docs/sql/create_aggregate_agent_jobs.sql)

Adjust `@TargetDb` if the database name is not `EPMS`.

### 3. Verify SQL Agent jobs

Check:

```sql
USE msdb;
GO
SELECT name, enabled
FROM dbo.sysjobs
WHERE name IN (N'EPMS Aggregate Hourly', N'EPMS Aggregate Rollup');
```

### 4. If SQL Agent becomes the primary scheduler

Remove Windows scheduled tasks on the app server to avoid double execution:

- [unregister_aggregate_tasks.ps1](/c:/Tomcat%209.0/webapps/ROOT/scripts/unregister_aggregate_tasks.ps1)

Example:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Tomcat 9.0\webapps\ROOT\scripts\unregister_aggregate_tasks.ps1"
```

## When To Keep Task Scheduler

Keep Task Scheduler if:

- SQL Server Agent is unavailable
- SQL Server Agent is stopped and cannot be enabled
- application-side deployment automation is preferred

Registration script:

- [register_aggregate_tasks.ps1](/c:/Tomcat%209.0/webapps/ROOT/scripts/register_aggregate_tasks.ps1)

## Operational Rule

- Never run both SQL Agent jobs and Windows scheduled tasks as active primaries at the same time
- Choose one scheduler as the production authority
- For new DB-server-centric environments, SQL Agent is the recommended authority
