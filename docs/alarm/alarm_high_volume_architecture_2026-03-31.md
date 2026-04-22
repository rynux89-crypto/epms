# Alarm High-Volume Architecture

## Goal

Prepare the alarm engine for large analog-tag volumes such as ~20,000 AI tags by
introducing explicit cache/state/batch abstractions before full runtime cutover.

## Added Java scaffolding

- `WEB-INF/src/epms/alarm/AlarmStateKey.java`
- `WEB-INF/src/epms/alarm/AlarmOpenState.java`
- `WEB-INF/src/epms/alarm/AlarmStateCache.java`
- `WEB-INF/src/epms/alarm/AlarmRuleCache.java`
- `WEB-INF/src/epms/alarm/AlarmWriteOp.java`
- `WEB-INF/src/epms/alarm/AlarmBatchWriter.java`
- `WEB-INF/src/epms/alarm/AlarmProcessingResult.java`
- `WEB-INF/src/epms/alarm/AlarmIngestService.java`

## Intended next use

1. Replace repeated `loadEnabledAiRuleDefs(...)` calls with `AlarmRuleCache`
   - Status: active through `AlarmFacade.loadEnabledAiRuleDefs(...)`
2. Replace repeated open-state DB lookups with `AlarmStateCache`
3. Collect open/close mutations in `AlarmBatchWriter`
4. Move `processAiEvents(...)` orchestration into `AlarmIngestService`
5. Keep JSP/servlet as request parsing only

## Why this matters

- Reduces DB round trips for repeated rule/state lookups
- Makes batch JDBC writes possible
- Gives the next migration step concrete service boundaries instead of one large
  JSP runtime function
