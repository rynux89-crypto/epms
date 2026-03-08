# EPMS AI Agent

EPMS(전력 모니터링) 시스템의 AI 질의 응답 기능을 위한 서버/관리 구성 문서입니다.

## 1) 시스템 개요

- 사용자 질문은 `epms/agent.jsp`로 전달됩니다.
- `agent.jsp`는 요청을 분기합니다.
- 규칙 기반으로 바로 처리 가능한 질문은 DB 조회 후 즉시 응답합니다.
- 그 외 질문은 Ollama 모델을 호출해 분류/계획/최종 답변을 생성합니다.
- 관리자 화면 `epms/agent_manage.jsp`에서 모델/캐시/타임아웃을 변경하면 즉시 반영됩니다.

## 2) 핵심 파일과 역할

- `epms/agent.jsp`
  - AI 에이전트 메인 엔드포인트
  - 요청 검증, Rate Limit, 의도 분석, DB 컨텍스트 조회, Ollama 호출, 응답 생성
- `epms/agent_manage.jsp`
  - 에이전트 운영 설정 화면
  - Ollama 등록 모델 조회(`/api/tags`), 모델 선택, 캐시/타임아웃 설정 저장
- `epms/agent_model.properties`
  - 런타임 설정 저장 파일
  - `agent_manage.jsp` 저장값을 `agent.jsp`가 매 요청 시 읽어 적용

## 3) 요청 처리 흐름 (`agent.jsp`)

1. HTTP/입력 검증
- `POST`만 허용
- `message` 길이 제한(최대 2000)
- IP 기준 Rate Limit

2. 규칙 기반 직접 처리
- 전압 평균, 알람 요약, 고조파/주파수/역률 이상치 등은 직접 SQL 조회 후 즉답

3. LLM 3단계 처리
- Stage 1: 분류 모델(`model`)로 DB 조회 필요 여부/파라미터 추론
- Stage 2: 코더 모델(`coder_model`)로 DB task 계획 및 SQL 성격 답변 초안
- Stage 3: 분류 모델(`model`)로 최종 사용자 답변 생성

4. 응답
- JSON 형태로 `provider_response`, `db_context` 반환

## 4) 모델/운영 설정

설정 파일: `epms/agent_model.properties`

- `model`
  - 기본 대화/분류/최종 응답 모델
- `coder_model`
  - DB/SQL 해석용 모델
- `schema_cache_ttl_minutes`
  - DB 스키마 자동 수집 캐시 유지 시간(분)
- `ollama_connect_timeout_seconds`
  - Ollama 연결 타임아웃(초)
- `ollama_read_timeout_seconds`
  - Ollama 응답 타임아웃(초)
- `updated_at`
  - 마지막 저장 시간(메타데이터)

## 5) 즉시 반영 정책

- `agent.jsp`는 요청마다 `agent_model.properties`를 읽습니다.
- 따라서 `agent_manage.jsp`에서 저장하면 Tomcat 재시작 없이 즉시 적용됩니다.
- 스키마 캐시 TTL 변경 시 내부 캐시 만료 시점을 갱신해 새 정책으로 동작합니다.

## 6) 스키마 자동 주입

- `agent.jsp`는 `INFORMATION_SCHEMA.TABLES/COLUMNS`를 조회해 스키마 컨텍스트를 생성합니다.
- 생성한 스키마는 캐시 후 코더 프롬프트에 자동 주입됩니다.
- 캐시 TTL은 `schema_cache_ttl_minutes`로 제어됩니다.

## 7) API

### `POST /epms/agent.jsp`

요청 예시:

```json
{"message":"최근 알람 요약 알려줘"}
```

응답 예시:

```json
{
  "provider_response": "{\"response\":\"...\",\"done\":true}\n",
  "db_context": "..."
}
```

주요 상태 코드:
- `200`: 성공
- `400`: 잘못된 요청(입력 오류, 모델 없음 등)
- `405`: 허용되지 않은 메서드
- `429`: Rate Limit 초과
- `500`: 서버 내부 오류
- `502`: Ollama 연결 실패

## 8) 관리 화면

### `GET/POST /epms/agent_manage.jsp`

기능:
- Ollama 모델 목록 조회
- `model`, `coder_model` 선택 저장
- `schema_cache_ttl_minutes` 설정
- Ollama 연결/응답 타임아웃 설정
- 기본값(환경변수 기반) 복원

## 9) 실행 전제

- Tomcat 9+
- Java 8+
- SQL Server (JNDI: `java:comp/env/jdbc/epms`)
- Ollama 서버 접근 가능 (`OLLAMA_URL`, 기본 `http://localhost:11434`)

## 10) 운영 체크 포인트

- 모델 교체 후 `agent_manage.jsp`에서 현재 적용값 확인
- 대형 모델 사용 시 `ollama_read_timeout_seconds` 상향
- 빈번한 스키마 변경 환경이면 `schema_cache_ttl_minutes`를 짧게 조정
