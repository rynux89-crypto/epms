# EPMS 원격검침 리팩토링 TODO

## 1. 목표

현재 원격검침 영역은 JSP 안에 아래 책임이 섞여 있다.

- HTTP 요청 처리
- 파라미터 파싱
- DB 연결 및 SQL 실행
- 업무 규칙 판단
- 프로시저 호출
- HTML 렌더링

리팩토링 목표는 이를 `도메인 중심 구조`로 분리하는 것이다.

- 매장/계측기 마스터 관리
- 원격검침 운영
- 정산/청구
- peak 관리

각 영역이 독립적으로 확장 가능하도록 코드 구조를 정리한다.

## 2. 리팩토링 원칙

- JSP는 화면 렌더링에 집중한다.
- 요청 처리와 업무 규칙은 Servlet/Service로 이동한다.
- SQL은 Repository 계층으로 분리한다.
- 정산 계산과 원격검침 운영 로직은 분리한다.
- 검증 로직은 공통 서비스로 모은다.
- 프로시저 호출은 Service에서 감싸고 사전/사후 검증을 붙인다.

## 3. 현재 주요 대상 파일

우선 리팩토링 대상은 아래 파일들이다.

- [tenant_store_manage.jsp](/c:/Tomcat%209.0/webapps/ROOT/epms/tenant_store_manage.jsp:1)
- [tenant_meter_map_manage.jsp](/c:/Tomcat%209.0/webapps/ROOT/epms/tenant_meter_map_manage.jsp:1)
- [tenant_billing_manage.jsp](/c:/Tomcat%209.0/webapps/ROOT/epms/tenant_billing_manage.jsp:1)
- [tenant_store_energy_detail.jsp](/c:/Tomcat%209.0/webapps/ROOT/epms/tenant_store_energy_detail.jsp:1)
- [epms_main.jsp](/c:/Tomcat%209.0/webapps/ROOT/epms/epms_main.jsp:1)
- [alter_epms_tenant_billing_for_store_open_close.sql](/c:/Tomcat%209.0/webapps/ROOT/docs/sql/alter_epms_tenant_billing_for_store_open_close.sql:1)
- [create_epms_tenant_billing_schema.sql](/c:/Tomcat%209.0/webapps/ROOT/docs/sql/create_epms_tenant_billing_schema.sql:1)

## 4. 최종 목표 구조

권장 패키지 구조 예시:

```text
WEB-INF/src/epms/tenant/
  controller/
  service/
  repository/
  model/
  validation/

WEB-INF/src/epms/remote/
  controller/
  service/
  repository/
  model/

WEB-INF/src/epms/billing/
  controller/
  service/
  repository/
  model/

WEB-INF/src/epms/peak/
  controller/
  service/
  repository/
  model/
```

## 5. 단계별 TODO

### Phase 1. 화면과 DB 접근 분리

#### TODO 1-1. 매장 관리 JSP의 SQL 분리

대상:

- [tenant_store_manage.jsp](/c:/Tomcat%209.0/webapps/ROOT/epms/tenant_store_manage.jsp:89)

할 일:

- 매장 조회 SQL을 `TenantStoreRepository`로 이동
- 매장 등록/수정/삭제 SQL을 Repository 메서드로 이동
- JSP에서 `openDbConnection()` 직접 호출 제거
- JSP에서 `PreparedStatement`, `ResultSet` 사용 제거

생성 후보:

- `WEB-INF/src/epms/tenant/repository/TenantStoreRepository.java`
- `WEB-INF/src/epms/tenant/service/TenantStoreService.java`

완료 기준:

- JSP에는 폼 렌더링과 결과 출력만 남는다.
- 등록/수정/삭제는 Service 호출로 처리된다.

#### TODO 1-2. 매장-계측기 연결 JSP의 SQL 분리

대상:

- [tenant_meter_map_manage.jsp](/c:/Tomcat%209.0/webapps/ROOT/epms/tenant_meter_map_manage.jsp:86)

할 일:

- 매핑 조회/등록/수정/삭제 SQL을 `TenantMeterMapRepository`로 이동
- `is_primary` 해제/재설정 로직을 Service로 이동
- JSP에서 기간/비율 파싱 로직 축소

생성 후보:

- `WEB-INF/src/epms/tenant/repository/TenantMeterMapRepository.java`
- `WEB-INF/src/epms/tenant/service/TenantMeterMapService.java`

완료 기준:

- `tenant_meter_map_manage.jsp`에서 SQL 문자열이 제거된다.
- `primary meter` 처리 규칙이 Service에 모인다.

#### TODO 1-3. 월 정산 JSP의 SQL 분리

대상:

- [tenant_billing_manage.jsp](/c:/Tomcat%209.0/webapps/ROOT/epms/tenant_billing_manage.jsp:29)
- [tenant_billing_manage.jsp](/c:/Tomcat%209.0/webapps/ROOT/epms/tenant_billing_manage.jsp:147)
- [tenant_billing_manage.jsp](/c:/Tomcat%209.0/webapps/ROOT/epms/tenant_billing_manage.jsp:158)

할 일:

- 요금제/계약/주기/청구서 조회 SQL 분리
- `ensureMonthlyCycle()` 로직을 Service로 이동
- 프로시저 실행 로직을 별도 Service 메서드로 이동
- 월 선택, 실행 가능 여부 판단, 상태 변경 로직 분리

생성 후보:

- `WEB-INF/src/epms/billing/repository/BillingRepository.java`
- `WEB-INF/src/epms/billing/service/BillingCycleService.java`
- `WEB-INF/src/epms/billing/service/BillingExecutionService.java`

완료 기준:

- JSP는 조회 결과 렌더링과 form action만 담당한다.
- 프로시저 실행 전/후 검증 포인트가 Service에 생긴다.

### Phase 2. 요청 처리와 화면 렌더링 분리

#### TODO 2-1. JSP 액션 처리 제거

대상:

- `tenant_store_manage.jsp`
- `tenant_meter_map_manage.jsp`
- `tenant_billing_manage.jsp`

할 일:

- POST 처리 코드를 Servlet으로 이동
- GET 조회용 컨트롤러와 POST 액션용 컨트롤러를 분리
- `msg`, `err`, redirect 조합을 공통 응답 패턴으로 통일

생성 후보:

- `TenantStoreServlet`
- `TenantMeterMapServlet`
- `TenantBillingServlet`

완료 기준:

- JSP 상단의 `if ("POST".equalsIgnoreCase(...))` 블록 제거
- 요청 분기와 화면 렌더링이 분리된다.

#### TODO 2-2. 화면 모델 DTO 도입

할 일:

- `Map<String, Object>` 기반 반환을 DTO로 대체
- 화면에서 필요한 값만 ViewModel로 정리

생성 후보:

- `TenantStoreRow`
- `TenantMeterMapRow`
- `BillingCycleRow`
- `BillingStatementRow`

완료 기준:

- 문자열 키 기반 접근이 줄어든다.
- 컴파일 시점 타입 검증이 가능해진다.

### Phase 3. 검증 로직 공통화

#### TODO 3-1. 매장/매핑/계약 기간 검증 서비스 도입

할 일:

- 매장 영업기간 검증
- 계측기 매핑 기간 중복 검증
- 계측기 매핑 공백 검증
- 계약기간 유효성 검증
- 폐점 매장의 정산 대상 여부 검증

생성 후보:

- `TenantBillingValidationService`
- `TenantMeterMapValidationService`

완료 기준:

- JSP에 흩어진 검증이 공통 메서드로 이동한다.
- 정산 전 사전 검증 로직을 재사용 가능하게 만든다.

#### TODO 3-2. 스냅샷 실행 사전검증 추가

대상:

- `sp_generate_billing_meter_snapshot` 호출 전

할 일:

- 선택 월에 유효한 매핑이 있는지 확인
- 정산 대상 매장 중 누락된 계약이 있는지 확인
- 측정 데이터가 아예 없는 계측기 사전 탐지
- 경고/오류 목록 반환

완료 기준:

- 버튼을 눌렀을 때 단순 실행이 아니라 실행 전 상태 점검이 가능하다.

### Phase 4. 도메인 분리

#### TODO 4-1. 원격검침과 정산 메뉴 분리

현 상태:

- `원격검침` 메뉴 안에 정산 화면이 강하게 섞여 있다.

할 일:

- `원격검침 운영`
- `매장 정산`
- `peak 관리`
메뉴를 분리

수정 대상:

- [epms_main.jsp](/c:/Tomcat%209.0/webapps/ROOT/epms/epms_main.jsp:225)

완료 기준:

- 사용자가 운영 화면과 정산 화면을 목적별로 구분해 접근할 수 있다.

#### TODO 4-2. 원격검침 전용 조회 모듈 분리

대상:

- [tenant_store_energy_detail.jsp](/c:/Tomcat%209.0/webapps/ROOT/epms/tenant_store_energy_detail.jsp:89)

할 일:

- 사용량 조회 로직을 `RemoteReadingService`로 이동
- 매장 상세 조회, 계측기 상세 조회, 일/월 사용량 계산을 분리
- 향후 peak/검침상태/이상탐지를 붙일 수 있도록 확장 포인트 확보

생성 후보:

- `WEB-INF/src/epms/remote/service/RemoteReadingService.java`
- `WEB-INF/src/epms/remote/repository/RemoteReadingRepository.java`

완료 기준:

- 매장 상세 화면은 조회 결과를 그리기만 한다.

### Phase 5. 프로시저 래핑과 계산 책임 정리

#### TODO 5-1. 프로시저 실행 래퍼 도입

대상:

- `sp_generate_billing_meter_snapshot`
- `sp_generate_billing_statement`

할 일:

- 프로시저 직접 호출을 Repository 또는 Gateway로 이동
- 호출 전후 로그 남기기
- 입력 파라미터 검증
- 실행 결과 요약 객체 반환

생성 후보:

- `BillingProcedureRepository`
- `BillingExecutionResult`

완료 기준:

- JSP/Servlet이 SQL 프로시저 호출 문자열을 직접 다루지 않는다.

#### TODO 5-2. 정산 계산 책임 분해

현 상태:

- 정산 로직의 핵심이 SQL 프로시저 안에 몰려 있다.

할 일:

- 프로시저는 유지하되 자바 서비스에서 사전 계산 조건을 관리
- 추후 15분 수요전력 기반 peak 계산을 별도 모듈로 분리
- 공용부/배분 정책은 SQL 한 곳에 숨기지 말고 문서와 코드에서 같이 드러내기

완료 기준:

- 계산 책임이 DB에만 묻히지 않고 코드 레벨에서도 추적 가능해진다.

### Phase 6. peak 관리 준비 리팩토링

#### TODO 6-1. peak 계산 모듈 독립

할 일:

- 현재 청구 프로시저 내 peak 계산을 추상화
- `instant peak`와 `billing peak`를 분리
- 15분 수요전력 계산 진입점을 마련

생성 후보:

- `PeakComputationService`
- `PeakPolicyRepository`

완료 기준:

- peak 로직을 정산 프로시저에서 독립시킬 수 있는 기반이 생긴다.

#### TODO 6-2. peak 정책 모델 도입

할 일:

- 매장별 peak 한도, 경고 단계, 제어 기준을 코드 구조상 먼저 반영
- 화면 구현 전이라도 model/service/repository 틀을 잡아둔다

완료 기준:

- 이후 peak 관리 기능 추가 시 기존 정산 코드와 충돌하지 않는다.

### Phase 7. 운영 진단 체계 준비

#### TODO 7-1. 검침 이슈 도메인 도입

할 일:

- 검침 누락, 역전, 이상치, 매핑 공백을 도메인 이벤트로 정의
- 향후 `billing_reading_issue` 테이블과 연결할 수 있게 구조 설계

생성 후보:

- `ReadingIssue`
- `ReadingIssueService`
- `ReadingIssueRepository`

완료 기준:

- 검침 품질 진단 기능이 정산 코드 안에 흩어지지 않는다.

#### TODO 7-2. 공통 상태 요약 서비스 도입

할 일:

- 매장 수
- 유효 매핑 수
- 최근 검침 상태
- 스냅샷 생성 상태
- 이슈 건수
요약을 제공하는 서비스 추가

생성 후보:

- `RemoteReadingDashboardService`

완료 기준:

- 대시보드 화면을 붙일 수 있는 집계 진입점이 생긴다.

## 6. 파일별 체크리스트

### tenant_store_manage.jsp

- SQL 제거
- POST 처리 제거
- `Map<String,Object>` 제거
- Service 호출로 전환

### tenant_meter_map_manage.jsp

- SQL 제거
- 기간 검증 로직 분리
- primary meter 규칙 Service화
- POST 처리 제거

### tenant_billing_manage.jsp

- 요금제/계약/주기/청구 조회 분리
- 프로시저 실행 분리
- 상태 변경 분리
- 실행 가능 여부 판단 로직 분리

### tenant_store_energy_detail.jsp

- 조회 SQL 분리
- 일/월 사용량 계산 로직 Service화
- 향후 peak/이상탐지 확장 지점 확보

### SQL 프로시저

- 입력/출력 계약 문서화
- 예외 상황별 반환 규칙 정리
- peak 계산 분리 준비

## 7. 우선순위 추천

가장 현실적인 착수 순서는 아래와 같다.

1. `tenant_billing_manage.jsp` 분리
2. `tenant_meter_map_manage.jsp` 분리
3. `tenant_store_manage.jsp` 분리
4. 공통 ValidationService 도입
5. `tenant_store_energy_detail.jsp` 조회 서비스화
6. peak 계산 모듈 독립

이 순서를 추천하는 이유는 `tenant_billing_manage.jsp`가 가장 많은 책임을 갖고 있고, 이후 peak/검침 이슈 기능의 병목이 되기 때문이다.

## 8. 완료 정의

리팩토링 완료는 단순히 파일이 작아지는 것이 아니다. 아래 상태가 되어야 한다.

- JSP가 직접 DB에 연결하지 않는다.
- 업무 규칙이 Service에 모여 있다.
- SQL이 Repository로 분리되어 있다.
- 원격검침과 정산 기능의 경계가 명확하다.
- peak 관리 기능을 추가할 공간이 구조적으로 확보되어 있다.
- 검침 예외 검증 기능을 새로 넣어도 기존 정산 화면이 더 복잡해지지 않는다.

## 9. 다음 액션

이 문서 다음 단계로 바로 진행할 수 있는 작업은 아래 둘 중 하나다.

1. `tenant_billing_manage.jsp`를 1차 분리 대상으로 잡고 Repository/Service 골격 생성
2. 공통 `ValidationService`부터 만들어 매핑/계약/정산 사전검증을 먼저 정리

권장 시작점은 `tenant_billing_manage.jsp` 분리다.
