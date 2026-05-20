# EPMS Code and Screen Design Analysis

Date: 2026-04-27

## 1. Executive Summary

EPMS is a Tomcat 9 JSP/Servlet application for electric power monitoring, power-quality analysis, energy reporting, PLC/Modbus operation, alarm/event handling, remote metering, billing, peak management, carbon emission calculation, and an Ollama-backed operator agent.

The system is practical and operator-focused. Its strongest architecture is in the Java-backed PLC, alarm, tenant, billing, peak, and carbon domains. Its weakest area is still the large JSP surface where SQL, request parsing, business logic, page rendering, inline CSS, and inline JavaScript are often mixed in one file.

## 2. Current Code Map

| Area | Files | Lines | Notes |
|---|---:|---:|---|
| `epms/` JSP pages | 58 | 28,611 | Main UI surface |
| `WEB-INF/src/epms` Java | 143 | 21,193 | Servlet, service, repository, utility code |
| `includes/` JSP fragments | 16 | 1,213 | DB, HTML, JSON, alarm helper fragments |
| `WEB-INF/jspf` JSP fragments | 3 | 154 | Runtime bridge fragments |
| `js/`, `css/` assets | 7 | 2,299 | Shared front-end assets |
| `docs/sql/src` SQL scripts | 20 | 4,431 | Schema and operational SQL |

## 3. Runtime Entry Points

Main screen:

- `epms/epms_main.jsp`

Servlet/API entry points from `WEB-INF/web.xml`:

- `/api/alarm` -> `epms.alarm.AlarmApiServlet`
- `/api/modbus` -> `epms.plc.ModbusApiServlet`
- `/api/agent` -> `epms.agent.AgentApiServlet`
- `/tenant-billing-action` -> `epms.billing.BillingManageServlet`
- `/tenant-store-action` -> `epms.tenant.TenantStoreManageServlet`
- `/tenant-meter-map-action` -> `epms.tenant.TenantMeterMapManageServlet`
- `/peak-policy-action` -> `epms.peak.PeakPolicyManageServlet`
- `/peak-management-action` -> `epms.peak.PeakManagementServlet`
- `/carbon-emission-action` -> `epms.carbon.CarbonEmissionManageServlet`

## 4. Functional Domains

### 4.1 Monitoring

Representative screens:

- `monitoring/meter_status.jsp`
- `monitoring/pq_overview.jsp`
- `monitoring/phasor_diagram.jsp`
- `monitoring/event_view.jsp`
- `monitoring/event_detail.jsp`
- `monitoring/alarm_view.jsp`
- `monitoring/alarm_detail.jsp`

Characteristics:

- Strong operator workflow coverage.
- Heavy JSP-side SQL and chart preparation.
- `event_detaul.jsp` is a typo-route compatibility redirect.

### 4.2 Quality Analysis

Representative screens:

- `quality/voltage_unbalance.jsp`
- `quality/current_unbalance.jsp`
- `quality/variation_ves.jsp`
- `quality/variation_ces.jsp`
- `quality/frequency_voltage.jsp`
- `quality/harmonics_v.jsp`
- `quality/harmonics_i.jsp`
- `quality/harmonic_detail.jsp`

Characteristics:

- Read-heavy analysis pages.
- Uses ECharts for time-series and harmonic visualization.
- Still mostly JSP-rendered with direct SQL access.

### 4.3 Energy and Carbon

Representative screens:

- `energy/energy_overview.jsp`
- `energy/energy_manage.jsp`
- `energy/energy_sankey.jsp`
- `energy/energy_meter_overview.jsp`
- `energy/energy_meter_detail.jsp`
- `energy/aggregated_measurements.jsp`
- `energy/carbon_emissions.jsp`

Java support:

- `epms.carbon.CarbonEmissionManageServlet`
- `epms.carbon.CarbonEmissionService`
- `epms.carbon.CarbonEmissionSchedulerListener`

Characteristics:

- Good coverage for usage trend, meter detail, aggregate lookup, and CO2 reporting.
- Carbon has moved partly into Java service code.

### 4.4 PLC and Modbus

Representative screens:

- `plc/plc_register.jsp`
- `plc/plc_status.jsp`
- `plc/plc_write.jsp`
- `plc/plc_excel_import.jsp`
- `plc/ai_mapping.jsp`
- `plc/di_mapping.jsp`
- `plc/ai_measurements_verify.jsp`
- `plc/ai_measurements_mapping_manage.jsp`
- `plc/harmonic_sync.jsp`

Java support:

- `epms.plc.ModbusApiServlet`
- `epms.plc.ModbusPollingSupport`
- `epms.plc.ModbusConfigRepository`
- `epms.plc.ModbusAiPersistService`
- `epms.plc.ModbusDiPersistService`
- `epms.plc.ModbusAlarmBridgeService`

Characteristics:

- Best-separated runtime domain in the codebase.
- Polling, config lookup, persistence, response building, and Modbus support are already separated.
- `plc_write.jsp` is still very large and contains static scheduler/cache/runtime state.

### 4.5 Alarm and Event

Representative screens:

- `monitoring/alarm_view.jsp`
- `monitoring/alarm_detail.jsp`
- `monitoring/event_view.jsp`
- `monitoring/event_detail.jsp`
- `system/alarm_rule_manage.jsp`
- `system/alarm_diag.jsp`

Java support:

- `epms.alarm.AlarmApiServlet`
- `epms.alarm.AlarmFacade`
- `epms.alarm.AlarmRuleRepository`
- `epms.alarm.AlarmPersistenceSupport`
- `epms.alarm.AlarmMessageRenderer`

Characteristics:

- Transitional architecture: meaningful Java services exist, but some diagnostic and management behavior is still JSP-heavy.
- Alarm diagnostics are valuable and should be preserved during refactoring.

### 4.6 Remote Metering, Tenant, Billing

Representative screens:

- `remote/tenant_store_manage.jsp`
- `remote/tenant_store_excel_import.jsp`
- `remote/tenant_meter_map_manage.jsp`
- `remote/tenant_meter_store_tiles.jsp`
- `remote/tenant_store_energy_detail.jsp`
- `remote/tenant_billing_manage.jsp`

Java support:

- `epms.tenant.*`
- `epms.remote.*`
- `epms.billing.*`

Characteristics:

- Better service/repository separation than older monitoring screens.
- Good candidate for continuing the same pattern across legacy JSP areas.

### 4.7 Peak Management

Representative screens:

- `peak/peak_management.jsp`
- `peak/peak_policy_manage.jsp`

Java support:

- `epms.peak.*`

Characteristics:

- Compact screen count with a relatively complete Java service/repository model.

### 4.8 Agent

Representative screen and assets:

- `agent/agent_manage.jsp`
- `js/epms_agent.js`
- `epms/agent/agent_model.properties`

Java support:

- `epms.agent.AgentApiServlet`
- `epms.agent.AgentApiRequestSupport`
- `epms.util.Agent*`

Characteristics:

- The feature is operationally rich.
- The util package is large, especially DB tooling and answer formatting.
- Future work should split intent routing, DB context building, answer formatting, and model calls into clearer packages.

## 5. Screen Design Analysis

Current visual language:

- Light operational dashboard theme.
- Card and panel components with soft shadows.
- Domain-colored sections on the main dashboard.
- ECharts and Chart.js for data visualization.
- Tables and filters are central to operator workflows.

Strengths:

- The main dashboard gives a clear domain map.
- KPI, table, filter, chart, and diagnostic screen patterns are already familiar to operators.
- The UI prioritizes actual operations over marketing-style pages.

Weaknesses:

- Inline CSS and inline JavaScript are common in JSP pages.
- Rounded pills and high-radius cards make the UI softer than a dense operations system needs.
- Some pages likely diverge visually because page-local styles override shared theme rules.
- `letter-spacing` was negative in the global heading style, which can make Korean headings visually crowded.

Recommended screen direction:

- Keep the light dashboard style.
- Use tighter 8px radii for buttons, panels, cards, badges, and inputs.
- Move repeated page-local CSS into shared classes in `css/main.css`.
- Prefer compact, scan-friendly tables and filters.
- Preserve domain color accents, but avoid adding more gradients.

## 6. Security and Operations Risks

High priority:

- `META-INF/context.xml` contains a plain DB username/password.
- `WEB-INF/config.toml` contains a plain DB password fallback.
- Historical scripts and SQL job templates previously contained legacy default database credentials; the current workspace removes those defaults except for the active Tomcat JNDI runtime setting documented in `docs/operations/epms_credential_externalization.md`.
- High-risk screens such as setup, retention/delete, PLC write, and imports need explicit authentication, authorization, and CSRF review.

Medium priority:

- Direct SQL in JSP increases review difficulty.
- Runtime state inside JSP declaration blocks is hard to lifecycle-manage during reloads.
- Large JSP files are difficult to test safely.

## 7. Refactoring Priorities

1. Externalize credentials and remove default plaintext passwords from committed runtime files.
2. Add or verify access control for setup, data retention, PLC write, import, and rule-management pages.
3. Move `plc_write.jsp` runtime logic into Java service classes.
4. Move `meter_status.jsp`, alarm rule management, and data retention logic behind Java services.
5. Consolidate shared DB access on `EpmsDataSourceProvider` or a single equivalent helper.
6. Extract repeated CSS and JavaScript into shared assets.
7. Retire typo/legacy route files after confirming no inbound links depend on them.

## 8. Immediate Safe Changes Completed

- Added this current-state analysis document.
- Adjusted shared UI tokens toward a cleaner operations-tool style in `css/main.css`.
- Added `EPMS_DB_*` environment-variable support for direct JDBC fallback in `includes/dbconfig.jspf`.
- Added the credential externalization note at `docs/operations/epms_credential_externalization.md`.
- Added an optional admin-token guard for high-risk JSP screens through `includes/epms_admin_guard.jspf`.
- Added the admin guard operating note at `docs/operations/epms_admin_guard.md`.
- Fixed direct JDBC SQL Server host normalization so `localhost,1433` style input is converted to JDBC `localhost:1433` syntax.
- Smoke-tested the main setup, dashboard, monitoring, PLC status, alarm, and energy overview screens with HTTP 200 responses.
- Added the smoke test record at `docs/operations/epms_smoke_test_2026-04-27.md`.
