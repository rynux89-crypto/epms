## Agent Formatter Split Plan

Current status on 2026-03-12:

- `epms/agent.jsp` now delegates `buildUserDbContext()` to `epms.util.AgentAnswerFormatter.buildUserDbContext(...)` first.
- `WEB-INF/src/epms/util/AgentAnswerFormatter.java` already formats many direct-answer contexts.
- JSP fallback still exists for runtime safety because Tomcat class reload timing is not always immediate.

### Already delegated in helper

These context families are implemented in `AgentAnswerFormatter.buildUserDbContext(...)`:

- `Meter:` / `Alarm:` wrapped combined context
- `[Latest alarms]`
- `[Latest meter readings]`
- `[Alarm count]`
- `[Monthly frequency avg]`
- `[Latest energy]`
- `[Energy delta]`
- `[Reactive energy delta]`
- `[Monthly power stats]`
- `[Alarm types]`
- `[Voltage unbalance TOP]`
- `[Harmonic exceed]`
- `[Power factor outlier]`
- `[Frequency outlier]`
- `[Open alarms]`
- `[Meter list]`
- `[Voltage phase angle]`
- `[Current phase angle]`
- `[Phase current]`
- `[Phase voltage]`
- `[Line voltage]`

### Still intentionally kept in JSP fallback

These remain in `epms/agent.jsp` `buildUserDbContext()` as safety rails:

- `meter_id required` -> `계측기를 지정해 주세요.`
- `phase required` / `invalid phase` -> `A/B/C 상을 지정해 주세요.`
- `Meter:` / `Alarm:` wrapper handling
- `[Latest meter readings]` formatting
- final generic raw-context fallback

Reason:

- Live tests showed helper delegation can lag until Tomcat reloads the updated class.
- Removing these too early can expose raw context like `[Phase voltage] meter_id required`.

### Recommended next removal order

Remove only after Tomcat app reload/restart and smoke test confirmation.

1. Remove duplicated formatter branches in JSP that helper already handles:
   - `Meter:` / `Alarm:` wrapper
   - `[Latest meter readings]`
2. Keep only user-facing guardrails in JSP:
   - `meter_id required`
   - `phase required`
   - `invalid phase`
3. If helper reload is verified stable, move those guardrails into helper too and shrink JSP fallback to:
   - delegate call
   - generic fallback only

### Smoke test checklist

Run after each reduction step:

- `현재 알람 상태는?`
- `77번 계측기 현재 상태는?`
- `주파수 이상치 보여줘`
- `A상 전압 보여줘`
- `77번 계측기 A상 전압 보여줘`
- `미해결 알람만 보여줘`

Expected:

- `provider_response` and `db_context_user` should both be formatted user text
- no raw tags like `[Phase voltage]`, `[Latest alarms]`, `meter_id=...`
