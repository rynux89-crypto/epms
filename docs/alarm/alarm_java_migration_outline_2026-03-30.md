# Alarm Java Migration Outline

## Goal

Move the alarm engine out of `epms/alarm_api.jsp` gradually, without breaking the current runtime path.

## First staged package

- `WEB-INF/src/epms/alarm/AlarmRuleDef.java`
- `WEB-INF/src/epms/alarm/AlarmOpenEvaluator.java`
- `WEB-INF/src/epms/alarm/AlarmMessageRenderer.java`
- `WEB-INF/src/epms/alarm/AlarmDerivedMetrics.java`
- `WEB-INF/src/epms/alarm/AlarmFacade.java`

These classes are intentionally pure Java helpers with no servlet or JSP dependency.

## Current state

Completed and stable:

1. Shared helper JSP fragments were split from `epms/alarm_api.jsp`
   - `includes/alarm_api_utils.jspf`
   - `includes/alarm_api_common_db.jspf`
   - `includes/alarm_api_ai_metrics.jspf`
   - `includes/alarm_api_di_helpers.jspf`
   - `includes/alarm_api_legacy.jspf`
2. Pure AI logic moved behind Java helpers
   - open/stage evaluation -> `AlarmOpenEvaluator`
   - message rendering -> `AlarmMessageRenderer`
   - unbalance/variation formulas -> `AlarmDerivedMetrics`
3. `AlarmFacade` became the main Java entry for JSP-facing alarm logic
4. AI rule loading now runs through Java-side repository/facade helpers
5. A servlet entrypoint exists at `/api/alarm`
6. `epms/alarm_api.jsp` and `/api/alarm` both point to the same runtime implementation

Still intentionally local in JSP:

- request-level AI / DI orchestration
- request parsing / JSON response writing for the legacy JSP path

These remain local because the next step is no longer pure helper extraction;
it is full request/service migration, which is larger and should be done as a
cohesive move.

## Recommended migration order

Phase 1: completed

1. Replace AI open/stage evaluation in `alarm_api.jsp` with `AlarmOpenEvaluator`
2. Replace AI message-template rendering with `AlarmMessageRenderer`
3. Replace derived-metric formulas with `AlarmDerivedMetrics`
4. Route JSP calls through `AlarmFacade` to reduce direct helper imports

Phase 2: next stable target

5. Introduce repository/service loading behind `AlarmFacade` or a servlet layer
   without making JSP import new repository classes directly
6. Move DB rule loading / open-close persistence into Java service/repository code

Phase 2: completed baseline

- `AlarmRuleRepository` is now active for AI rule loading
- `AlarmApiServlet` is now active as an additional controller entrypoint
- Servlet-side validation now handles:
  - `action` presence
  - `health`
  - `unknown action`
  - `POST` requirement for processing actions
  - `plc_id` requirement for processing actions
- The servlet now marks validated requests with request attributes so the
  runtime JSP can skip duplicate validation on the `/api/alarm` path

Phase 3: final shape

7. Move request-level `processAiEvents(...)` / `processDiEvents(...)` orchestration
   out of the runtime JSP into Java service classes
8. Keep `epms/alarm_api.jsp` as a thin compatibility shim only
9. Retire runtime JSP-local DTOs and remaining SQL blocks entirely

## Why this order

- Pure math / string rendering is easiest to verify
- No DB or servlet dependency means low wiring risk
- JSP can call static Java helpers first, then later migrate to service classes
- `AlarmFacade` gives JSP a single migration target before DB/service layers exist
- Direct repository wiring from JSP has shown runtime-specific risk here, so DB
  migration should happen only through a narrower, already-stable entrypoint
