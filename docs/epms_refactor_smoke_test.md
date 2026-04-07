# EPMS Refactor Smoke Test

## Scope

This checklist covers the JSP files refactored during the current EPMS cleanup work.

## Preconditions

- Tomcat is running with the current workspace deployed.
- The EPMS database is reachable through the configured JNDI datasource.
- Ollama is reachable if `agent.jsp` or `agent_manage.jsp` is tested.
- A test account and a non-production PLC target are available for write/poll tests.

## Core Runtime

### `epms/agent.jsp`

- Open `/epms/agent.jsp` through the existing chat UI.
- Ask one direct-answer question such as meter list or current alarm count.
- Ask one LLM-backed question that needs DB context.
- Expected:
  - JSON response shape is unchanged.
  - Direct-answer questions return without server error.
  - LLM-backed questions still return a normal response or a handled Ollama error.
- Quick check:
  - `powershell -ExecutionPolicy Bypass -File scripts/smoke_agent_api.ps1`

### `epms/agent_manage.jsp`

- Open `/epms/agent_manage.jsp`.
- Confirm current model settings render.
- Save the form with current values.
- Use `reset` once.
- Expected:
  - Model list loads or a handled error message appears.
  - Save updates `epms/agent_model.properties`.
  - Reset restores environment-based defaults without JSP failure.

### `epms/alarm_api.jsp`

- Trigger one DI-style request and one AI-style request with existing client flow.
- Verify alarm open/close still works from caller side.
- Expected:
  - JSON response contains `ok`, `opened`, `closed`.
  - `alarm_log` and `device_events` are updated as before.
  - No duplicate open alarms appear for the same active condition.
- Quick check:
  - `powershell -ExecutionPolicy Bypass -File scripts/smoke_alarm_api.ps1`

### `epms/plc/modbus_api.jsp`

- Call `polling_status`.
- Start polling for one configured PLC.
- Check `polling_snapshot`.
- Stop polling.
- Expected:
  - Status JSON renders correctly.
  - Poll state updates after start/stop.
  - DI/AI polling success and error counters still change normally.

### `epms/plc/plc_write.jsp`

- Open the write page.
- Run one single write against a safe test target.
- Start and stop write polling if that flow is enabled in the page.
- Expected:
  - Result JSON and page status still render.
  - Single-run and polling mode both update write state.
  - No null or malformed response body is returned.

## Admin CRUD

### `epms/meter_register.jsp`

- Add a test meter.
- Update the same meter.
- Delete the same meter.
- Expected:
  - Redirect messages render correctly.
  - List and filters remain usable after redirect.

### `epms/meter_tree_manage.jsp`

- Load page and child panel ajax.
- Add one relation, update it, then delete it.
- Expected:
  - Child panel ajax still returns valid data.
  - Add/update/delete redirects work and no cycle validation regression appears.

### `epms/alarm_rule_manage.jsp`

- Add one test alarm rule.
- Update it.
- Toggle enabled state.
- Delete it.
- Expected:
  - Validation messages still appear on invalid input.
  - Rule list reflects each operation immediately after redirect.

### `epms/metric_catalog_manage.jsp`

- Add one metric key.
- Update display name/source type.
- Rename the key.
- Toggle enabled state.
- Delete it.
- Expected:
  - Rename still propagates where supported.
  - Duplicate-key and missing-key validation still works.

### `epms/ai_measurements_mapping_manage.jsp`

- Add one match row.
- Update it.
- Delete it.
- Expected:
  - Token normalization remains uppercase.
  - Validation still blocks missing token or numeric fields.

### `epms/data_retention_manage.jsp`

- Load preview counts for 5, 7, and 10 years.
- Run backup with a safe backup path.
- Test delete flow only in a safe environment.
- Expected:
  - Preview counts load without JSP error.
  - Backup success/error message is shown cleanly.
  - Delete requires confirmation and refreshes counts after success.

## Mapping And Detail Pages

### `epms/ai_mapping.jsp`

- Open the page with existing query parameters.
- Confirm HTML output and any saved values still render safely.

### `epms/alarm_detail.jsp`

- Open detail view from alarm list.
- Expected:
  - Page loads without broken HTML escaping.

### `epms/event_detail.jsp`

- Open detail view from event list.
- Expected:
  - Page loads without broken HTML escaping.

### `epms/event_detaul.jsp`

- Open the typo route directly.
- Expected:
  - It redirects to `/epms/event_detail.jsp`.

## Read-Only Dashboards

### `epms/alarm_rule.jsp`

- Open the page and confirm token/metric lists load.

### `epms/alarm_view.jsp`

- Change filters and search.
- Open one detail row if linked.

### `epms/event_view.jsp`

- Change filters and search.
- Confirm event type and description formatting still look normal.

### `epms/energy_manage.jsp`

- Load the page with default dates.
- Change filters for building, usage, meter.
- Confirm charts and treemap still render.

### `epms/energy_overview.jsp`

- Open overview and verify all chart sections load.

### `epms/energy_sankey.jsp`

- Open default range and at least one filtered range.
- Confirm Sankey rendering still works.

### `epms/phasor_diagram.jsp`

- Open page with default selected meter.
- Change meter and verify the page and ajax refresh still work.

## Suggested Order

1. `agent_manage.jsp`
2. `agent.jsp`
3. `alarm_api.jsp`
4. `modbus_api.jsp`
5. `plc_write.jsp`
6. CRUD pages
7. Read-only dashboards

## Notes

- This is a smoke checklist, not a regression suite.
- Most recent changes are structural refactors, so the highest risk is broken request parsing, redirect flow, or response rendering.
- No runtime verification has been completed yet in this workspace.
