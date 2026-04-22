# EPMS (Electric Power Monitoring System)

EPMS는 전력 품질, 에너지, 알람, 이벤트, PLC 연동을 JSP/Servlet 기반으로 운영하는 웹 애플리케이션입니다.

## 1. 개요

- 런타임: Tomcat 9, JSP/Servlet
- DB: SQL Server
- 기본 경로: `epms/`
- 메인 화면: `epms/epms_main.jsp`
- Agent UI 스크립트: `js/epms_agent.js`

## 2. 현재 폴더 구조

메인 섹션 기준으로 화면을 아래처럼 정리해 두었습니다.

- `epms/epms_main.jsp`
- `epms/agent/`
- `epms/energy/`
- `epms/monitoring/`
- `epms/peak/`
- `epms/plc/`
- `epms/quality/`
- `epms/remote/`
- `epms/system/`

참고:

- `epms/` 루트에는 메인 진입 화면인 `epms_main.jsp`만 남기고, 나머지 화면은 섹션 폴더로 이동한 상태입니다.

## 3. 주요 기능 화면

### 3.1 Agent

- 관리 화면: `epms/agent/agent_manage.jsp`
- 설정 파일: `epms/agent/agent_model.properties`

### 3.2 Energy

- `epms/energy/energy_overview.jsp`
- `epms/energy/energy_manage.jsp`
- `epms/energy/energy_sankey.jsp`
- `epms/energy/energy_meter_overview.jsp`
- `epms/energy/energy_meter_detail.jsp`
- `epms/energy/aggregated_measurements.jsp`
- `epms/energy/carbon_emissions.jsp`

### 3.3 Monitoring

- `epms/monitoring/pq_overview.jsp`
- `epms/monitoring/meter_status.jsp`
- `epms/monitoring/phasor_diagram.jsp`
- `epms/monitoring/alarm_view.jsp`
- `epms/monitoring/alarm_detail.jsp`
- `epms/monitoring/event_view.jsp`
- `epms/monitoring/event_detail.jsp`

### 3.4 Peak

- `epms/peak/peak_management.jsp`
- `epms/peak/peak_policy_manage.jsp`

### 3.5 PLC

- `epms/plc/plc_register.jsp`
- `epms/plc/plc_status.jsp`
- `epms/plc/plc_write.jsp`
- `epms/plc/plc_excel_import.jsp`
- `epms/plc/ai_mapping.jsp`
- `epms/plc/di_mapping.jsp`
- `epms/plc/ai_measurements_verify.jsp`
- `epms/plc/ai_measurements_mapping_manage.jsp`
- `epms/plc/harmonic_sync.jsp`
- `epms/plc/modbus_api.jsp`

### 3.6 Quality

- `epms/quality/voltage_unbalance.jsp`
- `epms/quality/current_unbalance.jsp`
- `epms/quality/variation_ves.jsp`
- `epms/quality/variation_ces.jsp`
- `epms/quality/frequency_voltage.jsp`
- `epms/quality/harmonics_v.jsp`
- `epms/quality/harmonics_i.jsp`
- `epms/quality/harmonic_detail.jsp`

### 3.7 Remote

- `epms/remote/tenant_billing_manage.jsp`
- `epms/remote/tenant_meter_map_manage.jsp`
- `epms/remote/tenant_store_manage.jsp`
- `epms/remote/tenant_store_energy_detail.jsp`
- `epms/remote/tenant_store_excel_import.jsp`
- `epms/remote/tenant_meter_store_tiles.jsp`

### 3.8 System

- `epms/system/setup.jsp`
- `epms/system/meter_register.jsp`
- `epms/system/meter_tree_manage.jsp`
- `epms/system/meter_excel_import.jsp`
- `epms/system/alarm_rule_manage.jsp`
- `epms/system/metric_catalog_manage.jsp`
- `epms/system/data_retention_manage.jsp`
- `epms/system/di_group_manage.jsp`
- `epms/system/alarm_diag.jsp`

## 4. Agent 구성

### 4.1 주요 경로

- API 엔드포인트: `/api/agent`
- Agent 관리 화면: `epms/agent/agent_manage.jsp`
- Agent 설정 파일: `epms/agent/agent_model.properties`
- UI 스크립트: `js/epms_agent.js`

### 4.2 Agent 동작 요약

- 입력 질의를 분석해서 규칙 기반 직접 응답 가능 여부를 먼저 판단합니다.
- 알람/전력/계측기/전력품질 계열 질문은 DB 컨텍스트를 조회한 뒤 직접 응답하거나 LLM 응답에 보강합니다.
- 설명형 질문은 Ollama 모델을 사용해 내러티브형 응답을 생성합니다.
- 일부 질문은 특정 도메인 의도에 따라 PQ/Alarm 성격의 응답으로 유도됩니다.

### 4.3 최근 반영된 Agent 동작

- Agent 관리 화면은 `epms/agent/agent_manage.jsp`에서 한 화면으로 모델/채팅 UI를 관리합니다.
- 채팅 첫 화면에 샘플 질문 목록이 표시됩니다.
- `전체 건물의 현재 전력 사용 현황을 요약해줘` 같은 질문은 계측기별 최신 전력 데이터를 기반으로 요약 응답을 반환합니다.
- 현재 전력 요약 응답은 전체 계측기 수를 표시하면서, 기본적으로 표시 가능한 최신 계측기 데이터 범위를 기준으로 합계/평균/상위 계측기를 요약합니다.

### 4.4 관리 화면에서 조정 가능한 항목

- Ollama URL
- 기본 대화 모델 (`model`)
- 코더 모델 (`coder_model`)
- AI 모델 (`ai_model`)
- PQ 모델 (`pq_model`)
- Alarm 모델 (`alarm_model`)
- 스키마 캐시 시간 (`schema_cache_ttl_minutes`)
- 연결 타임아웃 (`ollama_connect_timeout_seconds`)
- 응답 타임아웃 (`ollama_read_timeout_seconds`)

## 5. Ollama URL 반영 방식

현재 코드는 아래 우선순위로 Ollama URL을 결정합니다.

1. `epms/agent/agent_model.properties`의 `ollama_url`
2. 환경변수 `OLLAMA_URL`
3. 기본값 `http://localhost:11434`

즉, 관리 화면에서 URL을 저장하면 이후 `/api/agent` 요청부터 즉시 적용됩니다.

## 6. 설정 파일 예시

### 6.1 `epms/agent/agent_model.properties`

```properties
ollama_url=http\://localhost\:11434
model=exaone-db\:latest
coder_model=qwen2.5-coder\:7b
ai_model=exaone-db\:latest
pq_model=exaone-db\:latest
alarm_model=exaone-db\:latest
schema_cache_ttl_minutes=60
ollama_connect_timeout_seconds=60
ollama_read_timeout_seconds=60
updated_at=2026-03-08 20\:23\:55
```

### 6.2 `WEB-INF/config.toml`

EPMS 운영값을 한 곳에서 관리하기 위한 설정 파일입니다.

- 위치: `WEB-INF/config.toml`
- Agent 설정 파일 경로 등 공통 운영값을 관리합니다.
- 백업 스크립트와 일부 운영 화면에서 함께 사용합니다.

## 7. 실행 전제

- Tomcat 9+
- Java 8+
- SQL Server 연결 가능
- JNDI 리소스 또는 direct JDBC fallback 구성
- Ollama 서버 접근 가능
- 공통 운영 설정 파일: `WEB-INF/config.toml`

## 8. 초기 설정

초기 서버에서 아래 화면을 통해 기본 설정을 진행할 수 있습니다.

- 진입 화면: `/epms/system/setup.jsp`

주요 기능:

- `WEB-INF/config.toml` 저장
- SQL Server 직접 연결 테스트
- 스키마 초기화
- PLC master 테이블 초기화
- 서버별 백업 Job SQL 생성
- seed 데이터 생성/삭제

권장 순서:

1. `/epms/system/setup.jsp` 접속
2. DB 서버/DB명/계정 입력 후 `Save + Test DB`
3. 정상 연결 확인 후 `Save + Initialize Schema`
4. 이후 `/epms/epms_main.jsp` 접속

## 9. 운영 체크리스트

- `/epms/epms_main.jsp` 정상 로딩 확인
- `epms/agent/agent_manage.jsp`에서 모델 저장 후 `/api/agent` 응답 확인
- `epms/monitoring/alarm_view.jsp`, `epms/monitoring/event_view.jsp`, `epms/monitoring/meter_status.jsp` 스모크 테스트
- `epms/energy/carbon_emissions.jsp` 및 에너지 관련 화면 확인
- 모델 변경 시 `/api/tags` 확인
- 타임아웃은 모델 크기와 응답 시간에 맞게 조정
- JSP/클래스 수정 후 런타임 반영이 애매하면 Tomcat 재시작

## 10. 임시 파일 정리 정책

루트에 생성되던 임시 JSON 테스트 파일은 정리했습니다.

- 작은 테스트 요청 파일 `tmp_*.json`은 삭제
- 큰 스냅샷 파일은 `archive/tmp_json/`으로 이동

현재 보관 위치:

- `archive/tmp_json/tmp_perf_snapshot.json`
- `archive/tmp_json/tmp_plc_snapshot.json`
- `archive/tmp_json/tmp_plc_snapshot2.json`

원칙:

- 루트에는 운영에 필요한 파일만 둡니다.
- 디버깅/스냅샷 산출물은 `archive/` 또는 별도 임시 폴더로 이동합니다.

## 11. 참고

- 일부 과거 오타 파일이나 호환 목적 파일이 남아 있을 수 있습니다.
  - 예: `epms/monitoring/event_detaul.jsp`
- 실제 메인에서 사용하는 경로와 문서 경로가 다를 수 있으므로, 신규 작업 시에는 현재 폴더 구조를 우선 기준으로 확인하는 것이 좋습니다.

## 12. 배포 절차

### 12.1 백업

1. 현재 운영 소스 백업
2. SQL Server 백업 수행
3. 주요 설정 파일 백업
   - `epms/agent/agent_model.properties`
   - `WEB-INF/config.toml`

### 12.2 반영

1. 최신 코드 반영
   - 예: `git pull origin master`
2. Tomcat `webapps/ROOT` 기준 파일 업데이트
3. 권한/경로 확인
4. 필요 시 Tomcat 재기동

### 12.3 검증

1. `/epms/epms_main.jsp` 접근 확인
2. 주요 화면 접근 확인
3. `/api/agent` 응답 확인
4. 최근 데이터 조회/저장 기능 점검
5. Tomcat 로그 확인

### 12.4 롤백 기준

아래 조건 중 하나라도 발생하면 즉시 롤백합니다.

- 메인/핵심 화면 접속 불가
- Agent 응답 불가 또는 지속적 5xx
- 주요 조회/저장 기능 실패

롤백 절차:

1. 백업 소스 복원
2. 필요 시 DB 백업본 복구
3. Tomcat 재기동 후 재검증
