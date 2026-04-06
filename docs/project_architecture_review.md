# EPMS Project Architecture Review

## 1. Overview

This project is a Tomcat 9 based EPMS (Electric Power Monitoring System) web application centered on JSP pages, SQL Server, PLC/Modbus integration, alarm/event processing, and an Ollama-backed agent feature.

Core runtime characteristics:

- UI layer: mostly JSP under `epms/`
- Shared JSP logic: `includes/` and `WEB-INF/jspf/`
- Java service/runtime layer: `WEB-INF/src/epms/`
- Database: SQL Server via JNDI `jdbc/epms`
- Deployment shape: exploded Tomcat webapp under `webapps/ROOT`

Main entrypoint:

- `epms/epms_main.jsp`

Servlet API entrypoints:

- `/api/alarm` -> `WEB-INF/src/epms/alarm/AlarmApiServlet.java`
- `/api/modbus` -> `WEB-INF/src/epms/plc/ModbusApiServlet.java`


## 2. Directory Map

### Root-level

- `epms/`: primary application JSP pages
- `WEB-INF/src/epms/`: Java source for alarm, plc, util
- `WEB-INF/jspf/`: JSP fragment runtime logic
- `includes/`: shared JSP include helpers
- `docs/sql/`: schema and supplemental SQL scripts
- `META-INF/context.xml`: Tomcat datasource definition
- `css/`, `js/`: shared front-end assets

### Major application areas

- Monitoring / PQ / energy: `epms/*.jsp`
- PLC operations: `epms/plc/*`
- Alarm / event: `epms/alarm_*.jsp`, `epms/event_*.jsp`
- Agent: `epms/agent.jsp`, `epms/agent_manage.jsp`


## 3. Functional Domains

### 3.1 Power monitoring and quality analysis

Representative pages:

- `epms/meter_status.jsp`
- `epms/pq_overview.jsp`
- `epms/phasor_diagram.jsp`
- `epms/voltage_unbalance.jsp`
- `epms/current_unbalance.jsp`
- `epms/frequency_voltage.jsp`
- `epms/harmonics_v.jsp`
- `epms/harmonics_i.jsp`
- `epms/harmonic_detail.jsp`

Characteristics:

- Traditional JSP-driven rendering
- Many pages open DB connections directly
- SQL is commonly embedded in JSP files
- Best suited to read-heavy operator dashboards

### 3.2 Energy management

Representative pages:

- `epms/energy_overview.jsp`
- `epms/energy_manage.jsp`
- `epms/energy_sankey.jsp`
- `epms/aggregated_measurements.jsp`

Characteristics:

- Mostly report/query style screens
- Depend on `measurements` and aggregate tables

### 3.3 PLC / Modbus runtime

Representative UI:

- `epms/plc/plc_register.jsp`
- `epms/plc/plc_status.jsp`
- `epms/plc/plc_write.jsp`
- `epms/plc/plc_excel_import.jsp`
- `epms/ai_mapping.jsp`
- `epms/di_mapping.jsp`
- `epms/ai_measurements_verify.jsp`

Java runtime:

- `WEB-INF/src/epms/plc/ModbusApiServlet.java`
- `WEB-INF/src/epms/plc/ModbusApiActionSupport.java`
- `WEB-INF/src/epms/plc/ModbusConfigRepository.java`
- `WEB-INF/src/epms/plc/ModbusPollingSupport.java`
- `WEB-INF/src/epms/plc/ModbusPollingExecutionSupport.java`
- `WEB-INF/src/epms/plc/ModbusCycleSupport.java`
- `WEB-INF/src/epms/plc/ModbusAiPersistService.java`
- `WEB-INF/src/epms/plc/ModbusDiPersistService.java`

Characteristics:

- More structured than the rest of the app
- Clear runtime state object for polling
- Explicit separation for config lookup, polling, persistence, API response building
- This is the strongest candidate area for continued service-layer refactoring

### 3.4 Alarm and event processing

Representative UI:

- `epms/alarm_view.jsp`
- `epms/alarm_detail.jsp`
- `epms/alarm_rule.jsp`
- `epms/alarm_rule_manage.jsp`
- `epms/alarm_diag.jsp`
- `epms/event_view.jsp`
- `epms/event_detail.jsp`

Entry/runtime:

- `epms/alarm_api.jsp`
- `WEB-INF/jspf/alarm_api_runtime.jsp`
- `WEB-INF/src/epms/alarm/AlarmApiServlet.java`
- `WEB-INF/src/epms/alarm/AlarmFacade.java`

Characteristics:

- Hybrid area
- Diagnostic and helper logic exist in Java classes
- A meaningful portion of actual runtime behavior still lives in JSPF includes
- Good observability exists, but boundary between legacy and refactored code is still blurry

### 3.5 Agent subsystem

Representative files:

- `epms/agent.jsp`
- `epms/agent_manage.jsp`
- `epms/agent_model.properties`
- `WEB-INF/src/epms/util/*`

Characteristics:

- Large monolithic JSP endpoint
- Performs rate limiting, DB retrieval, schema caching, intent parsing, model routing, and Ollama calls
- Operationally useful, but structurally oversized for long-term maintenance


## 4. Runtime Architecture

### 4.1 Request handling model

The application currently uses three patterns side by side:

1. JSP page with inline SQL and rendering
2. JSP page delegating to include fragments for shared logic
3. Servlet endpoint backed by Java service/helper classes

This mixed model explains why some areas feel modernized while others remain strongly legacy.

### 4.2 Database access

Common JNDI datasource:

- `java:comp/env/jdbc/epms`

Definitions:

- `META-INF/context.xml`
- `includes/dbconfig.jspf`
- `WEB-INF/src/epms/util/EpmsDataSourceProvider.java`

Patterns observed:

- JSP pages commonly use `openDbConnection()` from `includes/dbconfig.jspf`
- Newer Java PLC code uses `EpmsDataSourceProvider`
- Similar DB access helpers are duplicated in multiple places

### 4.3 PLC polling

Current behavior:

- Poll runtime is stored in servlet context
- PLC states are held in memory
- Background scheduler reads DI/AI data and persists results
- `start_polling` and `stop_polling` explicitly control runtime start/stop

Recent operational behavior now enforced:

- Polling is no longer auto-started by snapshot/status view alone
- User action is required to start server-side PLC polling

### 4.4 Alarm runtime

Current alarm behavior is transitional:

- Diagnostic state is available through Java classes
- Some direct DB writes still happen in runtime JSPF code
- Queue diagnostics exist, but current queue behaves more like in-memory write-op tracking than a true batch persistence pipeline


## 5. Database Shape

Schema source:

- `docs/sql/create_epms_schema.sql`

Broad table groups:

- Measurements and aggregates
- Harmonic measurements
- Alarm rules and alarm logs
- Device events
- Meter/device master data
- PLC configuration and PLC AI samples
- Mapping/helper tables for AI/DI integration

Operational note:

- The SQL documentation is valuable and should be treated as a first-class artifact because a lot of domain knowledge is encoded in the schema and supplemental indexes.


## 6. Strengths

- Strong operator focus: many admin and diagnostic pages exist for real operational workflows.
- PLC runtime is noticeably more structured than older areas.
- Alarm diagnostics provide useful observability.
- SQL documentation exists in `docs/sql`.
- Main dashboard UX is reasonably organized and readable.
- The application already contains enough separation points to support gradual refactoring rather than a full rewrite.


## 7. Key Risks

### 7.1 Security risk

`META-INF/context.xml` currently contains database credentials in plain text.

Impact:

- High operational exposure
- Deployment environment coupling
- Increases leakage risk if source tree is copied or backed up insecurely

### 7.2 Maintainability risk

There are very large monolithic JSP files.

Examples:

- `epms/agent.jsp`
- `epms/meter_status.jsp`
- `epms/alarm_rule_manage.jsp`
- `epms/ai_measurements_verify.jsp`

Impact:

- Harder onboarding
- Higher regression risk
- Difficult testing and code review

### 7.3 Architectural inconsistency

Different subsystems use different patterns:

- inline SQL in JSP
- shared JSPF includes
- Servlet + Java services

Impact:

- New contributors must learn multiple styles
- Refactoring boundaries are unclear
- Reuse and testing are weaker than they could be

### 7.4 Encoding and text integrity

There are visible signs of broken Korean text in some sources and generated scripts.

Examples observed:

- comments/messages in some JSP and Java files
- generated SQL script headers

Impact:

- Operator-facing wording may degrade
- Editing can become risky if file encodings are inconsistent

### 7.5 Logic concentration in JSP runtime

Alarm and agent areas still contain substantial business logic directly in JSP/JSPF.

Impact:

- Harder to unit test
- Harder to version behavior changes safely
- Runtime failures are harder to isolate


## 8. Largest Maintenance Hotspots

### 8.1 `epms/agent.jsp`

Rough size:

- about 6900 lines

Concerns:

- multiple responsibilities in one endpoint
- DB querying, routing, rate limiting, prompt orchestration, and model IO combined

Recommendation:

- split into request parsing, DB context builders, model gateway, and response assembly services

### 8.2 `epms/meter_status.jsp`

Concerns:

- central monitoring surface
- likely high change frequency
- inline SQL + rendering + client logic density

Recommendation:

- gradually extract data assembly into helper/service classes or JSON endpoints

### 8.3 Alarm runtime includes

Representative file:

- `WEB-INF/jspf/alarm_api_runtime.jsp`

Concerns:

- runtime business logic embedded in JSPF
- awkward boundary between legacy and refactored alarm code

Recommendation:

- move runtime processing to Java services while keeping JSP/API contracts stable


## 9. Refactoring Roadmap

### Phase 1: Stabilize operations

Priority: highest

- Externalize DB credentials from `META-INF/context.xml`
- Normalize file encodings to UTF-8 where possible
- Remove or isolate broken-text files before further edits
- Standardize datasource access on one shared Java provider
- Document runtime entrypoints and ownership

### Phase 2: Consolidate service boundaries

Priority: high

- Continue the PLC pattern in other domains
- Move alarm runtime business logic from JSPF to Java classes
- Introduce thin JSP controllers or JSON endpoints for heavy query pages
- Reduce direct SQL in UI-heavy JSP pages where change frequency is high

### Phase 3: Decompose monoliths

Priority: high

- Break `agent.jsp` into smaller service components
- Split giant JSP pages into reusable sections or backing APIs
- Introduce clearer separation between page rendering and data retrieval

### Phase 4: Improve observability and testing

Priority: medium

- Add structured logging around PLC and alarm operations
- Add smoke-test scripts for major pages and APIs
- Add targeted unit tests for Java service classes
- Expose clearer runtime health endpoints where useful

### Phase 5: Rationalize duplicate and legacy artifacts

Priority: medium

- Decide whether `pages/` is still needed alongside `epms/`
- Remove obsolete typo/legacy files when safe
- Consolidate duplicated DB helper logic and query helpers


## 10. Recommended Near-Term Focus

If only a small amount of engineering time is available, the best sequence is:

1. secure datasource configuration
2. fix encoding consistency
3. extract alarm runtime from JSPF
4. split `agent.jsp`
5. gradually move large read-heavy pages behind cleaner service APIs


## 11. Summary

This codebase is a practical operator-facing EPMS that has clearly evolved through real usage. Its strongest pattern today is the PLC subsystem, where runtime responsibilities are separated into Java services. Its weakest pattern is the concentration of business logic in very large JSP files, especially in the agent and legacy alarm paths.

The project does not need a rewrite to improve substantially. A staged cleanup focused on security, encoding, service boundary consistency, and decomposition of the largest JSPs would produce meaningful gains without destabilizing operations.
