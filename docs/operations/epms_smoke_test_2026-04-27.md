# EPMS Smoke Test Results

Date: 2026-04-27

## Environment

- App root: `C:\Tomcat 9.0\webapps\ROOT`
- Base URL: `http://localhost:8080`
- SQL Server endpoint for JDBC: `localhost:1433`
- SQL Server database: `EPMS`

## Database Connectivity

Verified from the host:

```text
sqlcmd -S localhost,1433 -U sa -P <password> -C
```

Results:

- SQL Server service is running.
- TCP port `1433` is reachable.
- `EPMS` database exists.
- `dbo.meters` is queryable.

Important note:

- `sqlcmd` accepts `localhost,1433`.
- Microsoft JDBC expects `localhost:1433`.
- EPMS now normalizes `host,port` to `host:port` in the direct JDBC fallback path.

## HTTP Smoke Test

The following screens returned `HTTP 200` with no fatal JSP/SQL error patterns:

| Screen | Result |
|---|---|
| `/epms/system/setup.jsp` | OK |
| `/epms/epms_main.jsp` | OK |
| `/epms/monitoring/meter_status.jsp?meter_id=0` | OK |
| `/epms/plc/plc_status.jsp` | OK |
| `/epms/monitoring/alarm_view.jsp` | OK |
| `/epms/energy/energy_overview.jsp` | OK |

The following admin-guarded screens also returned `HTTP 200` when `EPMS_ADMIN_TOKEN` was not set, preserving existing behavior:

| Screen | Result |
|---|---|
| `/epms/system/setup.jsp` | OK |
| `/epms/system/data_retention_manage.jsp` | OK |
| `/epms/system/alarm_rule_manage.jsp` | OK |
| `/epms/system/metric_catalog_manage.jsp` | OK |
| `/epms/system/meter_excel_import.jsp` | OK |
| `/epms/plc/plc_write.jsp` | OK |
| `/epms/plc/plc_excel_import.jsp` | OK |
| `/epms/remote/tenant_store_excel_import.jsp` | OK |

## Working Tree Check

`git diff --check` completed without whitespace errors after normalizing touched JSP files to LF line endings.
