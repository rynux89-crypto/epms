# EPMS AI Assistant

**Electrical Power Monitoring System (EPMS)** 통합 챗봇으로, Ollama 기반의 LLM(대형 언어 모델)을 사용하여 전력 품질 모니터링 데이터에 대한 실시간 질의 응답을 제공합니다.

## 🎯 주요 기능

- **AI 챗봇 통합**: 모든 EPMS 페이지에 채팅 위젯 통합
- **실시간 시스템 컨텍스트**: 데이터베이스에서 현재 미터 측정값과 알람 정보를 조회하여 LLM에 제공
- **스트리밍 응답**: Ollama의 스트리밍 API를 활용한 실시간 응답 생성
- **보안**: Rate limiting, 입력 검증, HTTP 메소드 제한
- **CPU 최적화**: Ollama llama2 모델 (7B, Q4_0 quantization) 사용 - CPU 환경에서 실행 가능

---

## 📋 시스템 요구사항

- **Java**: JDK 8+ (Tomcat 호환)
- **Tomcat**: 9.0.0+
- **Database**: SQL Server with JNDI DataSource (`java:comp/env/jdbc/epms`)
- **Ollama**: 0.15.0+ (localhost:11434)
- **LLM Model**: llama2:latest (또는 다른 Ollama 지원 모델)

---

## 🚀 빠른 시작

### 1단계: Ollama 설치 및 실행

#### Windows:
```powershell
# Ollama 다운로드 및 설치 (공식 사이트)
# https://ollama.ai

# Ollama 시작 (설치 후 자동으로 백그라운드 서비스로 실행)
ollama serve

# 또는 PowerShell에서 수동 실행:
& 'C:\Program Files\Ollama\ollama.exe' serve
```

### 2단계: 모델 설치

```powershell
# llama2 모델 다운로드 (약 3.8GB)
ollama pull llama2

# 모델 확인
curl http://localhost:11434/api/tags
```

### 3단계: 환경 변수 설정

```powershell
# Ollama URL (기본값: http://localhost:11434)
[System.Environment]::SetEnvironmentVariable("OLLAMA_URL", "http://localhost:11434", "User")

# Ollama 모델 (기본값: llama2)
[System.Environment]::SetEnvironmentVariable("OLLAMA_MODEL", "llama2", "User")

# 변수 확인
echo $env:OLLAMA_URL
echo $env:OLLAMA_MODEL
```

### 4단계: Tomcat 재시작
```powershell
cd "C:\Tomcat 9.0\bin"
./shutdown.bat
./startup.bat
```

### 5단계: 대시보드 접속
```
http://localhost:8080/
```

---

## 📂 파일 구조

```
webapps/ROOT/
├── index.jsp                 # 메인 대시보드
├── README.md                 # 이 파일
├── js/
│   ├── epms_agent.js         # 채팅 위젯 (클라이언트)
│   ├── chart.js              # 차트 라이브러리
│   └── echarts.js            # ECharts 라이브러리
├── css/
│   └── index.css
├── epms/
│   ├── agent.jsp             # LLM 포워딩 엔드포인트 (서버)
│   ├── epms_main.jsp         # EPMS 메인 페이지
│   └── [여러 EPMS 하위 페이지들]
├── includes/
│   ├── dbconfig.jspf         # DB 연결 설정
│   ├── dbconn.jsp            # DB 헬퍼
│   ├── header.jsp
│   └── footer.jsp
└── pages/
    └── [EPMS 페이지들]
```

---

## 💬 API 엔드포인트

### `/epms/agent.jsp`

**요청:**
```bash
curl -X POST http://localhost:8080/epms/agent.jsp \
  -H "Content-Type: application/json" \
  -d '{"message":"현재 시스템 상태는?"}'
```

**응답:**
```json
{
  "provider_response": "{\"model\":\"llama2\",...,\"response\":\"...\",\"done\":true}\n...",
  "db_context": "[Meters: M1:230.5V,M2:235.2V] | [Alarms: ...]"
}
```

**HTTP 상태 코드:**
- `200`: 성공
- `400`: 잘못된 요청 (입력 검증 실패, 모델 미발견)
- `405`: 메소드 불허 (POST만 허용)
- `429`: Rate limit 초과 (1분당 10개 요청 제한)
- `502`: Ollama 연결 실패

---

## 🔐 보안 기능

### 1. Rate Limiting
- **제한**: 1분당 IP당 최대 10개 요청
- **응답**: HTTP 429 (Too Many Requests)

### 2. 입력 검증
- **최대 길이**: 2000자
- **필수**: `message` 필드 필수
- **XSS 방지**: JSON 신뢰 구간 내에서 처리

### 3. 데이터베이스 보안
- **SQL Injection 방지**: Statement 사용 (PreparedStatement는 SELECT-only라 파라미터화 불필요하지만 입력은 검증)
- **연결 풀링**: JNDI DataSource를 통한 안전한 연결 관리

### 4. 통신 보안
- **Content-Type**: application/json 강제
- **CORS**: 같은 도메인 내 요청만 처리
- **Method**: POST만 허용

---

## 🛠️ 설정 파일

### `epms/agent.jsp`
- **LLM 엔드포인트**
- **역할**: 사용자 요청 → DB 컨텍스트 수집 → Ollama 요청 → 응답 릴레이
- **주요 기능**:
  - Rate limiting (메모리 기반)
  - DB 연결 및 컨텍스트 조회
  - Ollama `/api/generate` 호출
  - 스트리밍 응답 처리

### `js/epms_agent.js`
- **클라이언트 채팅 위젯**
- **역할**: UI 렌더링, 사용자 입력 수집, 응답 파싱 및 표시
- **기능**:
  - 모달 기반 대화 인터페이스
  - 스트리밍 JSON 파싱
  - 오류 처리 및 표시
  - DB 컨텍스트 하단 표시

### `includes/dbconfig.jspf`
- **데이터베이스 연결 헬퍼**
- **JNDI 이름**: `java:comp/env/jdbc/epms`
- **역할**: JSP에서 안전한 DB 연결 제공

---

## 📊 데이터베이스 쿼리

### 미터 측정값 (현재 구현)
```sql
SELECT TOP 5 meter_id, measurement_value 
FROM vw_meter_measurements 
ORDER BY measurement_time DESC
```

### 알람 정보 (현재 구현)
```sql
SELECT TOP 2 severity, alarm_message 
FROM alarm_detail 
ORDER BY created_at DESC
```

**주의**: 실제 테이블 이름이 다르면 `epms/agent.jsp`의 `getRecentMeterContext()`, `getRecentAlarmContext()` 함수를 수정하세요.

---

## 🎨 UI 커스터마이징

### 채팅 위젯 스타일 수정
파일: [js/epms_agent.js](js/epms_agent.js#L10-L30)

```javascript
// 예: 버튼 색상 변경
.epms-chat-btn { background: #28a745; } // 초록색
```

### 시스템 프롬프트 수정
파일: [epms/agent.jsp](epms/agent.jsp#L140-L145)

```jsp
String systemPrompt = "당신은 시스템 관리자입니다. ...";
```

---

## 🧪 테스트

### 1. 엔드포인트 테스트
```powershell
$json = '{"message":"hello"}' | ConvertTo-Json
curl.exe -X POST http://localhost:8080/epms/agent.jsp `
  -H "Content-Type: application/json" `
  -d $json -s
```

### 2. Rate Limiting 테스트
```powershell
# 10개 이상의 요청 전송 → 429 상태 확인
for ($i=1; $i -le 15; $i++) {
  curl.exe -X POST http://localhost:8080/epms/agent.jsp `
    -H "Content-Type: application/json" `
    -d '{"message":"test"}' -s -w "%{http_code}\n"
}
```

### 3. 웹 UI 테스트
- `http://localhost:8080/` 접속
- "💬 EPMS Chat" 버튼 클릭
- 메시지 입력 후 전송
- 응답 확인

---

## 🐛 문제 해결

### 문제: "Model not found"
**원인**: Ollama에 모델이 설치되지 않음
```powershell
ollama pull llama2
```

### 문제: "Cannot reach Ollama"
**원인**: Ollama 서비스가 실행되지 않음
```powershell
# Ollama 서비스 재시작
ollama serve

# 또는 서비스 확인
Get-Service | grep ollama
```

### 문제: "Invalid message" (400)
**원인**: JSON 파싱 실패 또는 메시지 길이 초과 (> 2000자)
```json
// 올바른 형식
{"message":"당신의 메시지"}
```

### 문제: Rate limit 초과 (429)
**원인**: 1분 내에 10개 이상의 요청 전송
- 1분 대기 후 재시도

### 문제: DB 연결 실패
**원인**: JNDI DataSource 미설정
```xml
<!-- META-INF/context.xml에 다음 추가 -->
<Resource name="jdbc/epms" 
  type="javax.sql.DataSource"
  driverClassName="com.microsoft.sqlserver.jdbc.SQLServerDriver"
  url="jdbc:sqlserver://yourserver:1433;databaseName=epms"
  username="user" password="pass"
  maxActive="20" maxIdle="5" />
```

---

## 📈 성능 최적화

### 1. Ollama 모델 선택 (CPU 사용)
| 모델 | 크기 | 메모리 | 추천 |
|------|------|--------|------|
| llama2 | 3.8GB | ~8GB | ✅ (기본) |
| mistral | 4.1GB | ~8GB | ⭐ (더 빠름) |
| neural-chat | 3.8GB | ~8GB | ⭐ |
| orca-mini | 2GB | ~6GB | ✅ (가장 빠름) |

### 2. 응답 크기 조절
```jsp
// epms/agent.jsp
"max_tokens": 512  // 조정 가능 (512~2048)
"temperature": 0.7 // 0.0~1.0 (낮을수록 일관됨)
```

### 3. Rate Limiting 조절
```jsp
private static final int RATE_LIMIT_MAX_REQUESTS = 10; // 조정
private static final int RATE_LIMIT_WINDOW_MS = 60000; // 1분
```

---

## 📚 참고 자료

- **Ollama**: https://ollama.ai
- **Ollama API**: https://github.com/ollama/ollama/blob/main/docs/api.md
- **Tomcat**: https://tomcat.apache.org
- **SQL Server**: https://www.microsoft.com/sql-server

---

## 📝 라이선스 및 지원

**개발**: EPMS AI Division  
**버전**: 1.0.0  
**마지막 업데이트**: 2026-02-13

---

## 💡 향후 개선 사항

- [ ] WebSocket 기반 실시간 스트리밍
- [ ] 대화 기록 저장 (DB)
- [ ] 멀티 모델 지원 (Ollama + OpenAI)
- [ ] 사용자 인증 (AD/LDAP)
- [ ] 고급 프롬프트 템플릿
- [ ] 응답 캐싱
- [ ] 분석 대시보드 (질문/응답 통계)
