# EPMS Backup Migration Checklist

새 서버로 EPMS를 옮길 때 일일 백업 자동화는 자동으로 따라가지 않습니다.
프로젝트 파일은 복사되더라도 SQL Server Agent Job, 서비스 상태, 서버별 경로는 새 서버에서 다시 적용해야 합니다.

## Quick Start

### 신규 서버

1. [create_epms_schema.sql](/c:/Tomcat%209.0/webapps/ROOT/docs/sql/create_epms_schema.sql) 실행
2. EPMS 웹앱 배포
3. `C:\backup` 폴더 생성
4. [backup_epms_daily.ps1](/c:/Tomcat%209.0/webapps/ROOT/scripts/backup_epms_daily.ps1) 수동 테스트 실행
5. [create_epms_daily_backup_job.sql](/c:/Tomcat%209.0/webapps/ROOT/docs/sql/create_epms_daily_backup_job.sql) 변수 수정 후 실행
6. SQL Server Agent 시작

### 백업 복원 서버

1. 기존 EPMS DB 백업 복원
2. EPMS 웹앱 배포
3. `C:\backup` 폴더 생성
4. [backup_epms_daily.ps1](/c:/Tomcat%209.0/webapps/ROOT/scripts/backup_epms_daily.ps1) 수동 테스트 실행
5. [create_epms_daily_backup_job.sql](/c:/Tomcat%209.0/webapps/ROOT/docs/sql/create_epms_daily_backup_job.sql) 변수 수정 후 실행
6. SQL Server Agent 시작

## 1. 파일 배포

- 프로젝트를 새 서버의 웹 루트로 배포
- 백업 스크립트 확인: [backup_epms_daily.ps1](/c:/Tomcat%209.0/webapps/ROOT/scripts/backup_epms_daily.ps1)
- Job 생성 SQL 확인: [create_epms_daily_backup_job.sql](/c:/Tomcat%209.0/webapps/ROOT/docs/sql/create_epms_daily_backup_job.sql)

## 2. 서버별 값 확인

아래 값은 새 서버에 맞게 다시 확인해야 합니다.

- SQL Server 주소
- 데이터베이스 이름
- SQL 로그인 계정/비밀번호
- 백업 저장 경로
- EPMS 배포 경로
- SQL Server Agent 사용 가능 여부

기본 예시:

- SQL Server: `localhost,1433`
- Database: `EPMS`
- BackupDir: `C:\backup`
- ScriptPath: `C:\Tomcat 9.0\webapps\ROOT\scripts\backup_epms_daily.ps1`

## 3. 사전 준비

- 새 서버에 `C:\backup` 폴더 생성
- SQL Server Agent 서비스가 설치되어 있는지 확인
- SQL Server Agent 서비스 시작
- 백업 경로에 SQL Server/Agent 서비스 계정 쓰기 권한 부여

## 4. Job 재등록

- [create_epms_daily_backup_job.sql](/c:/Tomcat%209.0/webapps/ROOT/docs/sql/create_epms_daily_backup_job.sql) 상단 변수 수정
- 수정할 대표 값:
  - `@scriptPath`
  - `@dbServer`
  - `@dbName`
  - `@dbUser`
  - `@dbPassword`
  - `@backupDir`
  - `@retainDays`
  - `@startTime`
- SQL 실행

## 5. 동작 테스트

- PowerShell로 스크립트 단독 실행

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Tomcat 9.0\webapps\ROOT\scripts\backup_epms_daily.ps1" -Server "localhost,1433" -Database "EPMS" -User "sa" -Password "1234" -BackupDir "C:\backup" -RetainDays 7
```

- `C:\backup`에 `.bak` 생성 확인
- `logs\db_backup.log` 확인
- SQL Server Agent Job 수동 실행 확인

## 6. 운영 확인 항목

- 백업 파일이 매일 생성되는지 확인
- 7일 지난 백업이 자동 삭제되는지 확인
- 디스크 여유 공간 점검
- Agent 서비스 재시작 후에도 스케줄이 정상 동작하는지 확인

## 7. 권장 운영

- `SIMPLE` 복구 모델 유지 시:
  - 일일 전체 백업 1회
  - 7일 또는 14일 보관
- 경로 또는 계정이 바뀌면 Job을 다시 생성하거나 스텝 명령을 수정
- 운영 비밀번호를 SQL 파일에 고정하고 싶지 않으면 Job 스텝에서 `-User`, `-Password` 대신 환경변수 기반으로 운영하는 방식도 고려
