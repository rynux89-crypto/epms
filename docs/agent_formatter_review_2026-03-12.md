# Agent Formatter Review

Date: 2026-03-12

## Current Structure

- `epms/agent.jsp`
  - request handling, routing, DB query orchestration, direct-answer entrypoints
  - `buildUserDbContext()` now does:
    - first: delegate to `epms.util.AgentAnswerFormatter.buildUserDbContext(String)`
    - second: only a minimal generic string fallback if helper invocation fails
- `WEB-INF/src/epms/util/AgentAnswerFormatter.java`
  - primary owner of `db_context_user` formatting
  - handles:
    - meter/alarm wrapper contexts
    - latest meter status
    - alarm count / latest alarms / open alarms / alarm types
    - monthly frequency avg
    - energy / energy delta / reactive energy delta
    - monthly power stats
    - voltage unbalance / harmonic exceed / PF outlier / frequency outlier
    - phase current / phase voltage / line voltage
    - voltage/current phase angle
    - generic user-facing fallback text conversion

## What Changed

- JSP-side duplicated formatter branches inside `buildUserDbContext()` were removed.
- Helper formatting was extended so `db_context_user` is effectively owned by `AgentAnswerFormatter`.
- JSP still keeps a generic fallback path so runtime does not hard-fail if helper loading breaks.

## Verified After Tomcat Restart

- `current alarm status`
- `meter 77 current status`
- `frequency outlier`
- `A phase voltage`

Expected behavior:
- structured Korean answers are returned in both `provider_response` and `db_context_user`
- missing meter/phase inputs still resolve to user-friendly prompts

## Remaining Risk

- `agent.jsp` is still a large mixed-responsibility file.
- Helper formatting is compiled Java under `WEB-INF/classes`, so future changes still depend on class reload behavior.
- JSP retains a generic fallback path, which is good for safety but means ownership is not 100% single-path at runtime.

## Recommended Next Step

- Stop refactoring here unless there is a concrete new formatting problem.
- For future work, prefer:
  - adding new `db_context_user` formatting in `AgentAnswerFormatter`
  - keeping `agent.jsp` focused on query/result generation
  - validating with `scripts/smoke_agent_formatter.ps1`

## Quick Validation Command

```powershell
powershell -ExecutionPolicy Bypass -File scripts\smoke_agent_formatter.ps1 -TestGroup core
```
