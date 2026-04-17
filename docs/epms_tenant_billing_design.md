# EPMS Tenant Billing Design

## 목적

EPMS를 백화점/쇼핑몰용 매장 정산 시스템으로 확장하기 위한 설계입니다.  
기존 `meters`, `measurements` 중심 계측 스키마는 유지하고, 그 위에 매장 귀속, 검침 확정, 요금 계산, 청구 결과를 관리하는 정산 서브스키마를 추가합니다.

핵심 목표는 아래와 같습니다.

- 각 매장을 계량기와 연결한다.
- 검침 마감 시점의 누적 전력량을 확정 저장한다.
- 월 정산 주기별 사용량과 청구 금액을 재현 가능하게 남긴다.
- 실시간 화면과 정산 확정값을 분리한다.

## 왜 기존 스키마만으로 부족한가

기존 EPMS는 아래 두 값에는 강합니다.

- 현재 순간 사용량: `measurements.active_power_total`
- 누적 전력량: `measurements.energy_consumed_total`

하지만 백화점 매장 정산에는 아래 개념이 추가로 필요합니다.

- 어떤 계량기가 어느 매장 청구에 귀속되는가
- 검침 시작값/종료값이 무엇인가
- 어떤 단가/계약으로 계산했는가
- 최종 청구 금액이 얼마였는가
- 나중에 이의제기 시 어떤 기준으로 청구했는가

그래서 정산은 실시간 계측 테이블에서 직접 계산하지 않고, 정산 전용 테이블에 확정 결과를 저장해야 합니다.

## 추가 테이블

### `tenant_store`

매장 마스터입니다.

- 매장 코드
- 매장명
- 사업자번호
- 층/호실/구역
- 상태(`ACTIVE`, `CLOSED`)

### `tenant_meter_map`

매장과 계량기의 연결 테이블입니다.

- `store_id`
- `meter_id`
- `allocation_ratio`
- `billing_scope`
- `valid_from`, `valid_to`

이 테이블이 있어야 한 매장에 여러 계량기를 붙이거나, 한 계량기를 비율 배분으로 청구할 수 있습니다.

### `billing_cycle`

월 정산 주기 테이블입니다.

- `2026-03` 같은 `cycle_code`
- 시작일 / 종료일
- 검침 마감 시각
- 상태(`DRAFT`, `CLOSED`, `POSTED`)

### `billing_rate`

요금제 마스터입니다.

- kWh 단가
- 기본요금
- 수요요금 단가
- VAT 비율
- 전력산업기반기금 비율

### `tenant_billing_contract`

매장별 계약/요금제 적용 이력입니다.

- 매장
- 적용 요금제
- 계약 시작/종료일
- 계약전력
- 공용부 배부 비율

### `billing_meter_snapshot`

정산 확정 검침값입니다.

- 정산 주기
- 매장
- 계량기
- 시작 검침(`OPENING`) / 종료 검침(`CLOSING`)
- 확정 누적 kWh
- 자동/수동 여부
- 원본 측정 시각

정산의 기준점이 되는 가장 중요한 테이블입니다.

### `billing_statement`

매장별 월 청구서 헤더입니다.

- 시작 검침값
- 종료 검침값
- 사용량
- 최대수요
- 기본요금 / 사용요금 / 수요요금 / 조정금액
- VAT / 기금 / 총 청구금액
- 상태

### `billing_statement_line`

청구서 상세 라인입니다.

- 항목 유형
- 설명
- 수량
- 단가
- 금액

## 관계 요약

```text
tenant_store
  -> tenant_meter_map -> meters
  -> tenant_billing_contract -> billing_rate

billing_cycle
  -> billing_meter_snapshot -> meters
  -> billing_statement -> tenant_store

billing_statement
  -> billing_statement_line
```

## 월 정산 흐름

### 1. 매장/계량기 연결

운영자는 `tenant_store`와 `tenant_meter_map`을 관리합니다.

- A매장 -> `meter_id=52`
- B매장 -> `meter_id=18`
- 공용부는 비율 배분 필요 시 `allocation_ratio` 사용

### 2. 월 정산 주기 생성

예: 2026년 3월

- `cycle_code = 2026-03`
- `cycle_start_date = 2026-03-01`
- `cycle_end_date = 2026-03-31`

### 3. 시작/종료 검침값 생성

`sp_generate_billing_meter_snapshot`로 시작/종료 스냅샷을 생성합니다.

- 시작: 월초 기준 가장 가까운 누적값
- 종료: 월말 기준 가장 가까운 누적값
- 단, 매장 `opened_on`, `closed_on`이 있으면 월 정산 주기와 겹치는 실제 영업기간만 사용
- 즉 월중 오픈/폐점 매장은 영업 시작일 이후, 종료일 이전 구간만 정산

확정 후에는 이 값을 기준으로 정산합니다.

### 4. 청구서 생성

`sp_generate_billing_statement`를 실행합니다.

계산 기본식은 아래와 같습니다.

- 사용량 = 종료 검침값 - 시작 검침값
- 사용요금 = 사용량 × kWh 단가
- 수요요금 = 최대수요 또는 계약전력 × 수요요금 단가
- 총액 = 기본요금 + 사용요금 + 수요요금 + 조정금액 + VAT + 기금

영업기간 제약은 아래 순서로 함께 적용합니다.

- `billing_cycle.cycle_start_date ~ cycle_end_date`
- `tenant_store.opened_on ~ closed_on`
- `tenant_meter_map.valid_from ~ valid_to`
- `tenant_billing_contract.contract_start_date ~ contract_end_date`

### 5. 검토 및 발행

정산 담당자가 `billing_statement`를 검토한 뒤 상태를 확정/발행으로 변경합니다.

## 운영 원칙

- 실시간 화면은 `measurements`를 본다.
- 청구/정산은 `billing_meter_snapshot`, `billing_statement`를 본다.
- 과거 청구 재현은 반드시 스냅샷 기준으로 한다.
- 계량기 교체/통신 누락/누적값 점프는 스냅샷 단계에서 보정한다.
- 매장 오픈일 이전, 종료일 이후 사용량은 청구 계산에서 제외한다.

## 화면 방향

정산 목적 화면은 아래 순서가 적합합니다.

1. 매장 관리
2. 매장-계량기 연결 관리
3. 월 정산 주기 생성
4. 검침 확정 화면
5. 월 청구서 목록
6. 매장별 청구서 상세

## 적용 스크립트

정산 서브스키마 생성 스크립트:

- [create_epms_tenant_billing_schema.sql](/c:/Tomcat%209.0/webapps/ROOT/docs/sql/create_epms_tenant_billing_schema.sql)

이 스크립트는 기존 계측 스키마를 건드리지 않고 정산용 테이블/뷰/프로시저만 추가합니다.
