# EPMS (Electric Power Monitoring System)

EPMS는 전력 품질/에너지/알람/이벤트/PLC 매핑을 JSP 기반으로 운영하는 웹 애플리케이션입니다.

## 1. 개요

- 런타임: Tomcat 9, JSP/Servlet
- DB: SQL Server (JNDI 사용)
- 주요 경로: `epms/`
- 메인 화면: `epms/epms_main.jsp`

## 2. 주요 기능 화면

`epms_main.jsp` 기준으로 다음 화면으로 이동합니다.

- 전력 품질 통합: `pq_overview.jsp`
- 계측기 상세: `meter_status.jsp`
- 페이저 다이어그램: `phasor_diagram.jsp`
- 불평형/변동률: `voltage_unbalance.jsp`, `variation_ves.jsp`, `variation_ces.jsp`
- 주파수/전압 분석: `frequency_voltage.jsp`
- 고조파 분석: `harmonics_v.jsp`, `harmonics_i.jsp`, `harmonic_detail.jsp`, `harmonic_sync.jsp`
- 에너지 관리: `energy_overview.jsp`, `energy_manage.jsp`, `energy_sankey.jsp`
- 알람: `alarm_view.jsp`, `alarm_detail.jsp`, `alarm_rule.jsp`, `alarm_rule_manage.jsp`, `metric_catalog_manage.jsp`
- 이벤트: `event_view.jsp`, `event_detail.jsp`
- 계측기/트리 관리: `meter_register.jsp`, `meter_tree_manage.jsp`
- 데이터 보관/정리: `data_retention_manage.jsp`
- PLC/매핑: `plc_register.jsp`, `plc_status.jsp`, `plc_write.jsp`, `plc_excel_import.jsp`, `ai_mapping.jsp`, `di_mapping.jsp`, `ai_measurements_match.jsp`, `ai_measurements_match_manage.jsp`

## 3. AI Agent 구성

- API 엔드포인트: `epms/agent.jsp`
- 관리 화면: `epms/agent_manage.jsp`
- 설정 파일: `epms/agent_model.properties`

### 3.1 Agent 동작 요약

- 입력 검증, rate limit 처리
- 규칙 기반 즉답 가능한 질의는 DB 조회 후 응답
- 그 외 질의는 Ollama 모델 호출로 분류/생성 응답
- JSON 응답 반환

### 3.2 관리 화면에서 조정 가능한 항목

- Ollama URL
- 대화 모델 (`model`)
- 코더 모델 (`coder_model`)
- 스키마 캐시 시간 (`schema_cache_ttl_minutes`)
- 연결 타임아웃 (`ollama_connect_timeout_seconds`)
- 응답 타임아웃 (`ollama_read_timeout_seconds`)

## 4. Ollama URL 반영 방식

현재 코드는 다음 우선순위로 Ollama URL을 결정합니다.

1. `agent_model.properties`의 `ollama_url` (관리 화면 저장값)
2. 환경변수 `OLLAMA_URL`
3. 기본값 `http://localhost:11434`

즉, `agent_manage.jsp`에서 URL을 저장하면 `agent.jsp` 요청 시 즉시 해당 주소로 연결됩니다.

## 5. 설정 파일 예시 (`epms/agent_model.properties`)

```properties
ollama_url=http\://localhost\:11434
model=exaone-db\:latest
coder_model=qwen2.5-coder\:7b
schema_cache_ttl_minutes=60
ollama_connect_timeout_seconds=60
ollama_read_timeout_seconds=60
updated_at=2026-03-08 20\:23\:55
```

## 6. 실행 전제

- Tomcat 9+
- Java 8+
- SQL Server 연결 가능한 JNDI 리소스: `java:comp/env/jdbc/epms`
- Ollama 서버 접근 가능

## 7. 운영 체크리스트

- `agent_manage.jsp`에서 URL/모델 저장 후 `agent.jsp` 응답 확인
- 모델 변경 시 `/api/tags` 조회가 정상인지 확인
- 타임아웃은 모델 크기/응답시간에 맞게 조정
- 스키마 변경이 잦으면 캐시 시간을 짧게 조정

## 8. 참고

- 일부 JSP 파일명에 과거 오타 파일(`event_detaul.jsp`)이 남아 있을 수 있습니다.
- 메인에서 실제 사용하는 상세 화면은 `event_detail.jsp`입니다.
