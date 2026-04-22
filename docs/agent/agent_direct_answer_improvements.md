# Agent Direct Answer Improvements

## Scope

This note captures the direct-answer quality improvements applied to [`epms/agent.jsp`](/c:/Tomcat%209.0/webapps/ROOT/epms/agent.jsp).

The goal was to reduce cases where:

- a simple count question fell through to a generic context dump,
- list/top-N questions returned raw bracketed context,
- mixed meter/alarm questions answered only one side,
- alarm list answers were too long and repetitive.

## Improved Direct Answers

### Count And Summary

- meter count
- panel count
- building count
- usage type count
- alarm count
- open alarm count
- open alarm count by type
- severity summary
- alarm type summary

Example prompts:

- `현재 등록된 계측기 수를 알려줘`
- `동관 관련 패널 수를 알려줘`
- `현재 알람 수를 알려줘`
- `현재 열린 TRIP 알람 수를 알려줘`
- `현재 심각도별 알람 수를 알려줘`
- `현재 알람 종류별 수를 알려줘`

### Top-N And Outlier

- building power TOP
- voltage unbalance TOP
- harmonic exceed list
- power factor outlier list
- frequency outlier list

Example prompts:

- `건물별 전력 TOP 5를 알려줘`
- `전압 불평형 상위 5개 계측기를 알려줘`
- `고조파 이상 계측기 5개를 알려줘`
- `역률 이상 계측기 5개를 알려줘`
- `주파수 이상치 5개를 알려줘`

### Monthly Statistics

- monthly power stats
- monthly average frequency

Example prompts:

- `3번 계측기의 2월 평균 최대 전력을 알려줘`
- `3번 계측기의 2월 평균 주파수를 알려줘`
- `이번달 평균 주파수를 알려줘`

### Alarm Lists

- latest alarm list
- open alarm list
- compact alarm grouping for repeated severity/type
- shorter alarm description rendering using tag/point/address/bit extraction

Example prompts:

- `최근 알람을 보여줘`
- `현재 열린 알람 목록 5개를 보여줘`

### Combined Meter + Alarm

- recent meter state + recent alarm summary in a single answer

Example prompts:

- `최근 계측값과 알람을 같이 알려줘`
- `최근 계측 상태와 최근 알람을 보여줘`

## Formatting Changes

- Raw context such as `[Voltage unbalance TOP ...]` is converted to readable Korean output.
- Alarm descriptions no longer emit the full PLC DI sentence by default.
- Repeated alarm headers such as `ALARM/DI_TRIP` are compacted into one grouped phrase when possible.
- `buildUserDbContext(...)` now mirrors direct-answer formatters for the same context families, so fallback output stays readable.

## Verified Prompts

Verified through live `POST /epms/agent.jsp` checks:

- `전압 불평형 상위 5개 계측기를 알려줘`
- `오늘 전압 불평형 상위 3개 계측기를 알려줘`
- `현재 등록된 계측기 수를 알려줘`
- `현재 등록된 패널 수를 알려줘`
- `현재 등록된 건물 수를 알려줘`
- `현재 등록된 용도 수를 알려줘`
- `현재 알람 수를 알려줘`
- `동관 알람 수를 알려줘`
- `현재 열린 알람 수를 알려줘`
- `현재 열린 TRIP 알람 수를 알려줘`
- `현재 심각도별 알람 수를 알려줘`
- `현재 알람 종류별 수를 알려줘`
- `건물별 전력 TOP 5를 알려줘`
- `고조파 이상 계측기 5개를 알려줘`
- `역률 이상 계측기 5개를 알려줘`
- `주파수 이상치 5개를 알려줘`
- `3번 계측기의 2월 평균 최대 전력을 알려줘`
- `3번 계측기의 2월 평균 주파수를 알려줘`
- `최근 알람을 보여줘`
- `현재 열린 알람 목록 5개를 보여줘`
- `최근 계측값과 알람을 같이 알려줘`

## Known Limits

- Output quality still depends on intent routing order in `tryBuildDirectAnswer(...)`.
- Some prompts may still route into a nearby direct-answer family if the wording is too broad.
- Mixed alarm-type grouping is implemented, but current live data is dominated by `DI_TRIP`, so mixed-group formatting has not yet been observed in the latest runtime checks.
