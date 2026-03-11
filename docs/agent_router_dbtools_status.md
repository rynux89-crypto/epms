# Agent Router, Parser, DB Tools, And Formatter Status

This note captures the current extraction status of routing, query parsing, database-tool logic, answer formatting, specialized-answer dispatch, final response-flow policy, and output assembly from [`epms/agent.jsp`](/c:/Tomcat%209.0/webapps/ROOT/epms/agent.jsp) into Java helper classes.

## Router

Current router class:
- [`AgentQueryRouter.java`](/c:/Tomcat%209.0/webapps/ROOT/WEB-INF/src/epms/util/AgentQueryRouter.java)
- Compatibility fallback:
  - [`AgentQueryRouterCompat.java`](/c:/Tomcat%209.0/webapps/ROOT/WEB-INF/src/epms/util/AgentQueryRouterCompat.java)

Current responsibilities:
- Parse chat prefixes:
  - `/llm`
  - `/rule`
- Mark narrative prompts that should prefer LLM generation.
- Classify direct-answer intent families before DB work begins.

Intent families currently extracted into `AgentQueryRouter`:
- Meter summary and alarm summary
- Monthly frequency summary
- Per-meter power summary
- Harmonic summary
- Meter list and meter/panel/building/usage counts
- Alarm severity/type/count/open-count/list routing
- Building power top
- Panel latest status routing
- Harmonic exceed
- Frequency outlier
- Voltage unbalance top-N
- Power-factor outlier
- Voltage average summary
- Voltage/current phase angle
- Phase current / phase voltage / line voltage
- Active/reactive power
- Active/reactive energy
- Monthly power stats

`agent.jsp` usage pattern:
- `routedWantsXxx(...)` wrappers now resolve in this order:
  1. `AgentQueryRouter`
  2. `AgentQueryRouterCompat`
  3. Remaining local JSP fallback, only where still needed

Why the compat layer exists:
- In this environment, Tomcat/JSP classloading can temporarily keep an older `AgentQueryRouter` in memory.
- `AgentQueryRouterCompat` prevents `NoSuchMethodError` during that transition and keeps runtime behavior stable.

This means:
- Routing logic is now primarily owned by Java.
- Runtime safety is preserved during Tomcat/JSP classloader transitions.
- Fallback removal must be done conservatively, because classloader skew is a real runtime concern here.
- Some local JSP intent blocks have already been removed for:
  - meter/alarm count and list routing
  - top-N and outlier routing
  - active/reactive power and energy routing
  - phase/line voltage-current routing
  - monthly power-stat routing

## Parser

Current parser class:
- [`AgentQueryParser.java`](/c:/Tomcat%209.0/webapps/ROOT/WEB-INF/src/epms/util/AgentQueryParser.java)

Current responsibilities:
- Extract query-time parameters from raw user prompts.
- Keep token and time-window parsing outside JSP.

Parsing helpers currently extracted into `AgentQueryParser`:
- Phase label extraction
- Line-pair extraction
- Alarm type token extraction
- Alarm area token extraction
- Meter scope token extraction
- Top-N extraction
- Day-window extraction
- Explicit-day extraction
- Month extraction
- Meter-id extraction
- Panel token extraction
- Loose panel token extraction
- Explicit date extraction
- Time-window extraction
- Frequency threshold extraction
- Power-factor threshold extraction

`agent.jsp` usage pattern:
- Parser helpers call `AgentQueryParser` first through reflection.
- If the Java class or method is unavailable in the current runtime cycle, the JSP falls back to the old local implementation.

This means:
- Query parsing logic is no longer concentrated only in JSP.
- Runtime behavior stays stable during reload or partial deployment cycles.

## DB Tools

Current DB tools class:
- [`AgentDbTools.java`](/c:/Tomcat%209.0/webapps/ROOT/WEB-INF/src/epms/util/AgentDbTools.java)

Current responsibilities:
- Execute stable read-only DB queries used by direct answers.
- Return the same context-string format that `agent.jsp` already expects.

DB contexts currently extracted into `AgentDbTools`:
- Meter list
- Meter count
- Panel count
- Building count
- Usage count
- Alarm severity summary
- Alarm type summary
- Alarm count
- Open alarms
- Open alarm count
- Building power TOP
- Panel latest status
- Harmonic exceed list
- Frequency outlier list
- Voltage unbalance TOP-N
- Power-factor outlier list

`agent.jsp` usage pattern:
- Context getters call `invokeAgentDbTool(...)` first.
- If reflection fails, the JSP falls back to the original local SQL implementation.

This means:
- DB read logic is beginning to leave JSP.
- Response behavior stays stable because the returned context format is unchanged.

## Formatter

Current formatter class:
- [`AgentAnswerFormatter.java`](/c:/Tomcat%209.0/webapps/ROOT/WEB-INF/src/epms/util/AgentAnswerFormatter.java)

Current responsibilities:
- Convert stable context strings into final user-facing direct answers.
- Keep repeated natural-language formatting logic outside JSP.

Formatters currently extracted into `AgentAnswerFormatter`:
- Power-factor standard answer
- Voltage average answer
- Per-meter power answer
- Harmonic summary answer
- Monthly frequency answer
- Active or reactive power answer
- Active or reactive energy answer
- Energy-delta answer
- Alarm severity answer
- Alarm type answer
- Building power TOP answer
- Voltage unbalance TOP answer
- Harmonic exceed answer
- Power-factor outlier answer
- Frequency outlier answer
- Monthly power stats answer
- Latest alarms answer
- Open alarms answer

Shared formatting helpers currently extracted with it:
- Alarm description shortening
- Compact grouped alarm-list rendering

`agent.jsp` usage pattern:
- Formatter helpers call `AgentAnswerFormatter` first through reflection.
- If reflection fails, the JSP falls back to the original local formatter implementation.

This means:
- Direct-answer sentence construction is starting to leave JSP.
- Response wording stays stable while refactoring continues.

## Specialized Dispatch

Current specialized-dispatch helper:
- [`AgentSpecializedAnswerHelper.java`](/c:/Tomcat%209.0/webapps/ROOT/WEB-INF/src/epms/util/AgentSpecializedAnswerHelper.java)

Current responsibilities:
- Select the first specialized direct-answer branch after planner execution.
- Keep the branch-order policy outside JSP while preserving the existing formatter behavior.

Currently extracted decision targets:
- Harmonic summary
- Monthly frequency summary
- Per-meter power summary
- Meter list fallback path
- Phase current fallback path
- Phase voltage fallback path
- Line voltage fallback path

`agent.jsp` usage pattern:
- `tryBuildSpecializedAnswer(...)` calls `AgentSpecializedAnswerHelper.select(...)` first through reflection.
- The JSP still performs the final formatter call or `buildUserDbContext(...)` rendering.
- If the helper is unavailable in the current runtime cycle, the JSP falls back to the previous local branch tree.

This means:
- Specialized-answer branch ordering is no longer owned only by JSP.
- Formatter output remains unchanged while the dispatch layer is extracted.

## Response Flow

Current response-flow helper:
- [`AgentResponseFlowHelper.java`](/c:/Tomcat%209.0/webapps/ROOT/WEB-INF/src/epms/util/AgentResponseFlowHelper.java)

Current responsibilities:
- Decide when direct answers should be bypassed.
- Decide when specialized answers should be bypassed.
- Provide the rule-only fallback message.
- Apply direct-answer meter-count suffix policy.
- Build the final LLM prompt for DB-grounded or non-DB responses.

`agent.jsp` usage pattern:
- The JSP calls `AgentResponseFlowHelper` first through reflection.
- If the helper is unavailable in the current runtime cycle, the JSP falls back to the previous inline policy.

This means:
- Final response orchestration policy is no longer concentrated only in JSP.
- The remaining JSP logic is mostly request wiring, fallback handling, and final output writing.

## Output

Current output helper:
- [`AgentOutputHelper.java`](/c:/Tomcat%209.0/webapps/ROOT/WEB-INF/src/epms/util/AgentOutputHelper.java)

Current responsibilities:
- Build the final success JSON envelope returned by `POST /epms/agent.jsp`.
- Keep output escaping and payload assembly outside JSP.

`agent.jsp` usage pattern:
- `writeSuccessJson(...)` calls `AgentOutputHelper.buildSuccessJson(...)` first through a wrapper.
- If the helper is unavailable in the current runtime cycle, the JSP falls back to the previous inline JSON assembly.

This means:
- Output envelope construction is no longer owned only by JSP.
- The remaining inline path is now only a compatibility fallback.

## Verified Requests

Verified with live `POST /epms/agent.jsp` requests:
- Building count summary
- Meter list by area or scope
- Alarm count summary
- Open alarm count summary
- Building power TOP 5
- Voltage unbalance TOP 5
- Harmonic exceed list
- Power-factor outlier list with custom threshold such as `PF < 0.95`

Recent regression check:
- `Harmonic exceed` briefly regressed after `AgentDbToolsCompat` expansion.
- Root cause:
  - live Tomcat was still using an older `AgentAnswerFormatter` class while `agent.jsp` local fallback had already been updated for the newer `[Harmonic exceed] ... TV=... TI=...` context format.
- Current mitigation:
  - [`agent.jsp`](/c:/Tomcat%209.0/webapps/ROOT/epms/agent.jsp) now ignores delegated harmonic-exceed formatter output when it says "no exceeded meters" even though the context already contains populated `meter_id=` rows, and falls back to the updated local formatter.
- Current verified result:
  - `고조파 이상 계측기 5개를 알려줘` now returns populated meter rows again.

Power-factor outlier note:
- Default threshold is still `PF < 0.9`.
- Because of that, `역률 이상 계측기 5개를 알려줘` can legitimately return no results.
- Verified examples:
  - `역률 이상 계측기 5개를 알려줘` -> no outliers
  - `역률 0.95 미만 계측기 5개를 알려줘` -> populated result list
- Open alarm count summary
- Alarm type summary
- Building power TOP 5
- Panel latest status
- Harmonic exceed list
- Frequency outlier list
- Voltage unbalance TOP 5
- Power-factor outlier list
- Latest active power by meter
- Latest active energy by meter
- Monthly max or average power stats by meter
- Seven-day voltage average by meter
- Phase current, phase voltage, and line voltage by meter
- Harmonic summary by meter
- Power-factor standard answer
- Specialized harmonic, power, and phase-voltage dispatch paths
- Rule-only fallback and final LLM response-flow paths
- Success JSON envelope generation
- Narrative meter-and-alarm interpretation prompt
- Post-compat recovery checks:
  - Meter count summary
  - Open alarm count summary
  - Harmonic summary by meter

All of the above returned `200` during the current refactor cycle.

## Remaining Work

Still mainly inside [`epms/agent.jsp`](/c:/Tomcat%209.0/webapps/ROOT/epms/agent.jsp):
- Some remaining local formatters or summary builders
- Old local fallback paths that duplicate the extracted Java helpers
- Optional cleanup of old local fallback code after one more stabilization cycle

Recommended next step:
1. Keep `AgentQueryRouter`, `AgentQueryRouterCompat`, `AgentQueryParser`, `AgentDbTools`, `AgentAnswerFormatter`, `AgentSpecializedAnswerHelper`, `AgentResponseFlowHelper`, and `AgentOutputHelper` as the stable baseline.
2. Do not remove router fallbacks again until after a Tomcat restart and another live validation cycle.
3. If a servlet or controller migration is planned, move the remaining request and error response handling out of JSP next.
