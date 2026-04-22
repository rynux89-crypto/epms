# EPMS Refactor Stage 3 Status

## Scope

This document records the first stable batch of Stage 3 refactoring, where selected JSP helper logic was moved into Java classes under `WEB-INF/src` and compiled into `WEB-INF/classes`.

## Stable And Applied

The following Java utility classes are compiled and actively used by the running JSP pages.

- `WEB-INF/src/epms/util/EpmsWebUtil.java`
- `WEB-INF/src/epms/util/AgentSupport.java`
- `WEB-INF/src/epms/util/ModbusSupport.java`
- `WEB-INF/src/epms/util/PlcWriteSupport.java`

Compiled classes:

- `WEB-INF/classes/epms/util/EpmsWebUtil.class`
- `WEB-INF/classes/epms/util/AgentSupport.class`
- `WEB-INF/classes/epms/util/AgentSupport$RuntimeConfig.class`
- `WEB-INF/classes/epms/util/AgentSupport$HttpResponse.class`
- `WEB-INF/classes/epms/util/ModbusSupport.class`
- `WEB-INF/classes/epms/util/PlcWriteSupport.class`

Active JSP connections:

- `includes/epms_html.jspf`
- `includes/epms_parse.jspf`
- `includes/epms_json.jspf`
- `epms/agent.jsp`
  - uses `AgentSupport`
- `epms/plc/modbus_api.jsp`
  - uses `ModbusSupport`
- `epms/plc/plc_write.jsp`
  - uses `PlcWriteSupport`

## Prepared But Not Applied

The following class is compiled, but its JSP wiring is intentionally not active in the current stable state.

- `WEB-INF/src/epms/util/AgentTextUtil.java`
- `WEB-INF/classes/epms/util/AgentTextUtil.class`

Reason:

- During JSP recompilation, `agent.jsp` did not reliably resolve the new helper type in the current runtime cycle.
- The JSP was restored to local helper logic to keep runtime behavior stable.

## Runtime Check Baseline

These checks passed after the stable Stage 3 wiring was restored.

- `GET /epms/plc/modbus_api.jsp?action=polling_status` -> `200`
- `GET /epms/plc/plc_write.jsp?action=polling_status` -> `200`
- `GET /epms/agent.jsp` -> `405`
- `GET /epms/agent_manage.jsp` -> `200`

## Next Step

Recommended next action:

1. Commit this stable Stage 3 batch first.
2. Re-attempt `AgentTextUtil` wiring in a separate change after a clean Tomcat restart window.
