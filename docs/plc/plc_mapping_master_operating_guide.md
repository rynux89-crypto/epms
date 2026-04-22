# PLC Mapping Master Operating Guide

## 목적

현재 PLC 매핑 기준은 엑셀에서 출발하고, DB에서는 아래 마스터 테이블을 단일 기준으로 사용한다.

- `dbo.plc_ai_mapping_master`
- `dbo.plc_di_mapping_master`

알람/이벤트 처리 로직은 기존 구조를 유지한다.

## 기준 원칙

1. 최초 기준은 엑셀이다.
2. 엑셀 import 후 운영 기준은 마스터 테이블이다.
3. 화면 표시와 AI 적재는 마스터 테이블을 우선 참조한다.
4. 기존 구 테이블은 현재 fallback/호환용으로 남아 있다.

## AI 구조

주요 기준 테이블:
- `dbo.plc_ai_mapping_master`

주요 컬럼:
- `plc_id`
- `meter_id`
- `float_index`
- `token`
- `reg_address`
- `measurement_column`
- `target_table`
- `db_insert_yn`
- `enabled`
- `note`

운영 규칙:
- `17 -> KWH -> energy_consumed_total`
- `18 -> VA -> apparent_power_total`
- `19 -> VAH -> apparent_energy_total`
- `21 -> IR -> db_insert_yn = 0`

참고:
- `KHH` 는 마스터 적재 시 `KWH` 로 정규화한다.

## DI 구조

주요 기준 테이블:
- `dbo.plc_di_mapping_master`

주요 컬럼:
- `plc_id`
- `point_id`
- `di_address`
- `bit_no`
- `tag_name`
- `item_name`
- `panel_name`
- `enabled`
- `note`

운영 규칙:
- DI 읽기/조회 기준은 마스터를 우선 사용한다.
- 알람/이벤트 판단 로직 자체는 기존 코드 유지다.

## 화면별 참조 기준

다음 화면/로직은 현재 마스터를 우선 사용한다.

- [plc_status.jsp](c:/Tomcat%209.0/webapps/ROOT/epms/plc/plc_status.jsp)
  - AI/DI 표시
- [ai_measurements_mapping_manage.jsp](c:/Tomcat%209.0/webapps/ROOT/epms/ai_measurements_mapping_manage.jsp)
  - AI 목록 조회
  - 수정 시 AI 마스터 동기화
- [ai_measurements_verify.jsp](c:/Tomcat%209.0/webapps/ROOT/epms/ai_measurements_verify.jsp)
  - AI 검증 조회
- [di_mapping.jsp](c:/Tomcat%209.0/webapps/ROOT/epms/di_mapping.jsp)
  - DI 조회
- [plc_excel_import.jsp](c:/Tomcat%209.0/webapps/ROOT/epms/plc/plc_excel_import.jsp)
  - 현재 DB 매핑 비교표
- [ai_mapping.jsp](c:/Tomcat%209.0/webapps/ROOT/epms/ai_mapping.jsp)
  - AI 매핑 조회
- [plc_write.jsp](c:/Tomcat%209.0/webapps/ROOT/epms/plc/plc_write.jsp)
  - AI/DI 쓰기 보조 조회
- [harmonic_sync.jsp](c:/Tomcat%209.0/webapps/ROOT/epms/harmonic_sync.jsp)
  - harmonic 적재 기준
- [alarm_view.jsp](c:/Tomcat%209.0/webapps/ROOT/epms/alarm_view.jsp)
  - panel 목록 필터

## import 동작

[import_plc_mapping.ps1](c:/Tomcat%209.0/webapps/ROOT/scripts/import_plc_mapping.ps1) 는 현재 아래를 같이 수행한다.

1. 기존 테이블 반영
- `plc_meter_map`
- `plc_di_map`
- `plc_di_tag_map`

2. 마스터 동기화
- `plc_ai_mapping_master`
- `plc_di_mapping_master`

즉 엑셀 `적용` 후에는 마스터도 같은 트랜잭션 흐름으로 갱신된다.

## 실제 적재 흐름

1. PLC AI 읽기
2. `plc_ai_mapping_master` 기준으로 `token + float_index` 해석
3. `measurement_column`, `target_table`, `db_insert_yn` 기준으로 insert
4. `db_insert_yn = 0` 항목은 읽기만 하고 insert 하지 않음

예:
- `IR` 은 읽히지만 `measurements` 계열에 insert 하지 않음

## 확인 SQL

AI 핵심 매핑 확인:

```sql
SELECT plc_id, meter_id, float_index, token, reg_address, measurement_column, target_table, db_insert_yn
FROM dbo.plc_ai_mapping_master
WHERE meter_id = 18
  AND float_index IN (17, 18, 19, 21)
ORDER BY float_index;
```

DI panel 확인:

```sql
SELECT plc_id, point_id, di_address, bit_no, tag_name, item_name, panel_name, enabled
FROM dbo.plc_di_mapping_master
WHERE panel_name = N'DCP'
ORDER BY plc_id, point_id, di_address, bit_no;
```

최근 measurements 적재 확인:

```sql
SELECT TOP 10 meter_id, measured_at, energy_consumed_total, apparent_power_total, apparent_energy_total
FROM dbo.measurements
WHERE meter_id = 18
ORDER BY measured_at DESC;
```

## 운영 시 주의

1. 관리 화면에서 AI token/float_index를 바꾸면 실제 insert 대상 값이 바뀐다.
2. 엑셀 재적용이 기준이므로 운영 중 수동 수정 후에는 엑셀 원본도 같이 맞추는 것이 안전하다.
3. 알람/이벤트 로직은 유지 중이므로, 이번 구조 변경 범위는 매핑/조회/AI 적재 중심이다.
4. 구 테이블은 아직 남아 있으므로, 직접 SQL 수정은 마스터 기준으로 하는 것이 안전하다.

## 남은 fallback / 구 테이블 참조

현재 아래 항목은 아직 구 테이블을 직접 참조하거나, fallback 코드가 남아 있다.

우선 유지 권장:
- [ModbusConfigRepository.java](c:/Tomcat%209.0/webapps/ROOT/WEB-INF/src/epms/plc/ModbusConfigRepository.java)
  - 런타임은 마스터 우선, legacy fallback 기본 유지
- [ai_measurements_mapping_manage.jsp](c:/Tomcat%209.0/webapps/ROOT/epms/ai_measurements_mapping_manage.jsp)
  - 기존 `plc_ai_measurements_match` 저장 유지
- [import_plc_mapping.ps1](c:/Tomcat%209.0/webapps/ROOT/scripts/import_plc_mapping.ps1)
  - 기존 테이블 + 마스터 동기화 구조 유지

추후 정리 후보:
- [ai_measurements_verify.jsp](c:/Tomcat%209.0/webapps/ROOT/epms/ai_measurements_verify.jsp)
  - fallback SQL 및 설명 문구 최소화
- [ModbusConfigRepository.java](c:/Tomcat%209.0/webapps/ROOT/WEB-INF/src/epms/plc/ModbusConfigRepository.java)
  - PLC별 master row 존재 확인 후 legacy fallback 제거 검토
- [ai_measurements_mapping_manage.jsp](c:/Tomcat%209.0/webapps/ROOT/epms/ai_measurements_mapping_manage.jsp)
  - legacy 저장 의존 축소 검토

정리 원칙:
1. 알람/이벤트 운영 로직은 마지막까지 유지
2. 조회 화면 정리 후 런타임 fallback 제거
3. 마지막 단계에서 구 테이블 직접 참조 SQL 정리

## 런타임 fallback 스위치

[ModbusConfigRepository.java](c:/Tomcat%209.0/webapps/ROOT/WEB-INF/src/epms/plc/ModbusConfigRepository.java)는 기본적으로 legacy fallback을 켠 상태로 동작한다.

- JVM 속성: `-Depms.plc.legacyFallbackEnabled=false`
- 환경 변수: `EPMS_PLC_LEGACY_FALLBACK_ENABLED=false`

이 값을 `false`로 두면:
- AI map fallback (`plc_meter_map`) 비활성화
- DI tag fallback (`plc_di_tag_map`) 비활성화
- AI measurements match fallback (`plc_ai_measurements_match`) 비활성화

즉 master만으로 런타임을 검증할 수 있다. 운영 전환 시에는 먼저 readiness SQL 결과가 `READY_FOR_FALLBACK_REVIEW` 인지 확인하는 것을 권장한다.
