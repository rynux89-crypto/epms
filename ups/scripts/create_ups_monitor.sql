IF DB_ID(N'UPS_MONITOR') IS NULL
BEGIN
    CREATE DATABASE UPS_MONITOR;
END
GO

USE UPS_MONITOR;
GO

IF OBJECT_ID(N'dbo.ups_modbus_profile', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.ups_modbus_profile (
        profile_id int IDENTITY(1,1) NOT NULL CONSTRAINT PK_ups_modbus_profile PRIMARY KEY,
        profile_name nvarchar(100) NOT NULL,
        vendor_name nvarchar(100) NULL,
        model_name nvarchar(100) NULL,
        byte_order varchar(20) NOT NULL CONSTRAINT DF_ups_modbus_profile_byte_order DEFAULT ('BIG_ENDIAN'),
        word_order varchar(20) NOT NULL CONSTRAINT DF_ups_modbus_profile_word_order DEFAULT ('HIGH_WORD_FIRST'),
        enabled bit NOT NULL CONSTRAINT DF_ups_modbus_profile_enabled DEFAULT (1),
        note nvarchar(500) NULL,
        created_at datetime2(0) NOT NULL CONSTRAINT DF_ups_modbus_profile_created_at DEFAULT (sysdatetime()),
        updated_at datetime2(0) NOT NULL CONSTRAINT DF_ups_modbus_profile_updated_at DEFAULT (sysdatetime())
    );
END
GO

IF OBJECT_ID(N'dbo.ups_modbus_point', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.ups_modbus_point (
        point_id int IDENTITY(1,1) NOT NULL CONSTRAINT PK_ups_modbus_point PRIMARY KEY,
        profile_id int NOT NULL,
        metric_key varchar(80) NOT NULL,
        display_name nvarchar(100) NOT NULL,
        function_code tinyint NOT NULL,
        register_address int NOT NULL,
        register_count int NOT NULL CONSTRAINT DF_ups_modbus_point_register_count DEFAULT (1),
        data_type varchar(20) NOT NULL,
        scale_factor decimal(18,6) NOT NULL CONSTRAINT DF_ups_modbus_point_scale_factor DEFAULT (1),
        unit nvarchar(20) NULL,
        enabled bit NOT NULL CONSTRAINT DF_ups_modbus_point_enabled DEFAULT (1),
        sort_order int NOT NULL CONSTRAINT DF_ups_modbus_point_sort_order DEFAULT (0),
        created_at datetime2(0) NOT NULL CONSTRAINT DF_ups_modbus_point_created_at DEFAULT (sysdatetime()),
        updated_at datetime2(0) NOT NULL CONSTRAINT DF_ups_modbus_point_updated_at DEFAULT (sysdatetime()),
        CONSTRAINT FK_ups_modbus_point_profile FOREIGN KEY (profile_id) REFERENCES dbo.ups_modbus_profile(profile_id),
        CONSTRAINT CK_ups_modbus_point_function_code CHECK (function_code IN (3, 4))
    );
END
GO

IF OBJECT_ID(N'dbo.ups_modbus_point', N'U') IS NOT NULL
BEGIN
    IF COL_LENGTH('dbo.ups_modbus_point', 'register_count') IS NULL
    BEGIN
        ALTER TABLE dbo.ups_modbus_point ADD register_count int NOT NULL CONSTRAINT DF_ups_modbus_point_register_count DEFAULT (1);
    END
END
GO

IF OBJECT_ID(N'dbo.ups_device', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.ups_device (
        ups_id int IDENTITY(1,1) NOT NULL CONSTRAINT PK_ups_device PRIMARY KEY,
        ups_name nvarchar(100) NOT NULL,
        location nvarchar(200) NULL,
        ip_address varchar(45) NOT NULL,
        modbus_port int NOT NULL CONSTRAINT DF_ups_device_modbus_port DEFAULT (502),
        unit_id int NOT NULL CONSTRAINT DF_ups_device_unit_id DEFAULT (1),
        profile_id int NULL,
        rated_capacity_kva decimal(12,3) NULL,
        poll_interval_seconds int NOT NULL CONSTRAINT DF_ups_device_poll_interval_seconds DEFAULT (2),
        enabled bit NOT NULL CONSTRAINT DF_ups_device_enabled DEFAULT (1),
        last_comm_status varchar(20) NOT NULL CONSTRAINT DF_ups_device_last_comm_status DEFAULT ('UNKNOWN'),
        last_success_at datetime2(3) NULL,
        last_error_at datetime2(3) NULL,
        last_error_message nvarchar(500) NULL,
        created_at datetime2(3) NOT NULL CONSTRAINT DF_ups_device_created_at DEFAULT (sysdatetime()),
        updated_at datetime2(3) NOT NULL CONSTRAINT DF_ups_device_updated_at DEFAULT (sysdatetime()),
        CONSTRAINT FK_ups_device_profile FOREIGN KEY (profile_id) REFERENCES dbo.ups_modbus_profile(profile_id)
    );

    CREATE UNIQUE INDEX UX_ups_device_ip_unit ON dbo.ups_device(ip_address, modbus_port, unit_id);
END
GO

IF OBJECT_ID(N'dbo.ups_device', N'U') IS NOT NULL
BEGIN
    IF COL_LENGTH('dbo.ups_device', 'poll_interval_seconds') IS NULL
    BEGIN
        ALTER TABLE dbo.ups_device ADD poll_interval_seconds int NOT NULL CONSTRAINT DF_ups_device_poll_interval_seconds DEFAULT (2);
    END
END
GO

IF OBJECT_ID(N'dbo.ups_device', N'U') IS NOT NULL
BEGIN
    ALTER TABLE dbo.ups_device ALTER COLUMN last_success_at datetime2(3) NULL;
    ALTER TABLE dbo.ups_device ALTER COLUMN last_error_at datetime2(3) NULL;
    ALTER TABLE dbo.ups_device ALTER COLUMN created_at datetime2(3) NOT NULL;
    ALTER TABLE dbo.ups_device ALTER COLUMN updated_at datetime2(3) NOT NULL;
END
GO

IF OBJECT_ID(N'dbo.ups_measurement', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.ups_measurement (
        measurement_id bigint IDENTITY(1,1) NOT NULL CONSTRAINT PK_ups_measurement PRIMARY KEY,
        ups_id int NOT NULL,
        measured_at datetime2(3) NOT NULL,
        input_voltage decimal(12,3) NULL,
        output_voltage decimal(12,3) NULL,
        output_voltage_l12 decimal(12,3) NULL,
        output_voltage_l23 decimal(12,3) NULL,
        output_voltage_l31 decimal(12,3) NULL,
        output_current decimal(12,3) NULL,
        output_current_l1 decimal(12,3) NULL,
        output_current_l2 decimal(12,3) NULL,
        output_current_l3 decimal(12,3) NULL,
        output_power_kw decimal(12,3) NULL,
        output_power_l1_kw decimal(12,3) NULL,
        output_power_l2_kw decimal(12,3) NULL,
        output_power_l3_kw decimal(12,3) NULL,
        output_apparent_l1_kva decimal(12,3) NULL,
        output_apparent_l2_kva decimal(12,3) NULL,
        output_apparent_l3_kva decimal(12,3) NULL,
        output_apparent_total_kva decimal(12,3) NULL,
        output_pf_l1 decimal(9,4) NULL,
        output_pf_l2 decimal(9,4) NULL,
        output_pf_l3 decimal(9,4) NULL,
        load_percent decimal(9,3) NULL,
        frequency decimal(9,3) NULL,
        battery_voltage decimal(12,3) NULL,
        battery_current decimal(12,3) NULL,
        battery_charge_percent decimal(9,3) NULL,
        battery_temperature decimal(9,3) NULL,
        remaining_minutes decimal(12,3) NULL,
        ups_operation_mode_code int NULL,
        system_operation_mode_code int NULL,
        bypass_status_code int NULL,
        energy_storage_status_code int NULL,
        input_status_code int NULL,
        output_status_code int NULL,
        switchgear_status_code int NULL,
        battery_breaker_status_code int NULL,
        raw_status int NULL,
        created_at datetime2(3) NOT NULL CONSTRAINT DF_ups_measurement_created_at DEFAULT (sysdatetime()),
        CONSTRAINT FK_ups_measurement_device FOREIGN KEY (ups_id) REFERENCES dbo.ups_device(ups_id)
    );

    CREATE INDEX IX_ups_measurement_device_time ON dbo.ups_measurement(ups_id, measured_at DESC);
END
GO

IF OBJECT_ID(N'dbo.ups_measurement', N'U') IS NOT NULL
BEGIN
    IF COL_LENGTH('dbo.ups_measurement', 'output_voltage_l12') IS NULL ALTER TABLE dbo.ups_measurement ADD output_voltage_l12 decimal(12,3) NULL;
    IF COL_LENGTH('dbo.ups_measurement', 'output_voltage_l23') IS NULL ALTER TABLE dbo.ups_measurement ADD output_voltage_l23 decimal(12,3) NULL;
    IF COL_LENGTH('dbo.ups_measurement', 'output_voltage_l31') IS NULL ALTER TABLE dbo.ups_measurement ADD output_voltage_l31 decimal(12,3) NULL;
    IF COL_LENGTH('dbo.ups_measurement', 'output_current_l1') IS NULL ALTER TABLE dbo.ups_measurement ADD output_current_l1 decimal(12,3) NULL;
    IF COL_LENGTH('dbo.ups_measurement', 'output_current_l2') IS NULL ALTER TABLE dbo.ups_measurement ADD output_current_l2 decimal(12,3) NULL;
    IF COL_LENGTH('dbo.ups_measurement', 'output_current_l3') IS NULL ALTER TABLE dbo.ups_measurement ADD output_current_l3 decimal(12,3) NULL;
    IF COL_LENGTH('dbo.ups_measurement', 'output_power_l1_kw') IS NULL ALTER TABLE dbo.ups_measurement ADD output_power_l1_kw decimal(12,3) NULL;
    IF COL_LENGTH('dbo.ups_measurement', 'output_power_l2_kw') IS NULL ALTER TABLE dbo.ups_measurement ADD output_power_l2_kw decimal(12,3) NULL;
    IF COL_LENGTH('dbo.ups_measurement', 'output_power_l3_kw') IS NULL ALTER TABLE dbo.ups_measurement ADD output_power_l3_kw decimal(12,3) NULL;
    IF COL_LENGTH('dbo.ups_measurement', 'output_apparent_l1_kva') IS NULL ALTER TABLE dbo.ups_measurement ADD output_apparent_l1_kva decimal(12,3) NULL;
    IF COL_LENGTH('dbo.ups_measurement', 'output_apparent_l2_kva') IS NULL ALTER TABLE dbo.ups_measurement ADD output_apparent_l2_kva decimal(12,3) NULL;
    IF COL_LENGTH('dbo.ups_measurement', 'output_apparent_l3_kva') IS NULL ALTER TABLE dbo.ups_measurement ADD output_apparent_l3_kva decimal(12,3) NULL;
    IF COL_LENGTH('dbo.ups_measurement', 'output_apparent_total_kva') IS NULL ALTER TABLE dbo.ups_measurement ADD output_apparent_total_kva decimal(12,3) NULL;
    IF COL_LENGTH('dbo.ups_measurement', 'output_pf_l1') IS NULL ALTER TABLE dbo.ups_measurement ADD output_pf_l1 decimal(9,4) NULL;
    IF COL_LENGTH('dbo.ups_measurement', 'output_pf_l2') IS NULL ALTER TABLE dbo.ups_measurement ADD output_pf_l2 decimal(9,4) NULL;
    IF COL_LENGTH('dbo.ups_measurement', 'output_pf_l3') IS NULL ALTER TABLE dbo.ups_measurement ADD output_pf_l3 decimal(9,4) NULL;
    IF COL_LENGTH('dbo.ups_measurement', 'ups_operation_mode_code') IS NULL ALTER TABLE dbo.ups_measurement ADD ups_operation_mode_code int NULL;
    IF COL_LENGTH('dbo.ups_measurement', 'system_operation_mode_code') IS NULL ALTER TABLE dbo.ups_measurement ADD system_operation_mode_code int NULL;
    IF COL_LENGTH('dbo.ups_measurement', 'bypass_status_code') IS NULL ALTER TABLE dbo.ups_measurement ADD bypass_status_code int NULL;
    IF COL_LENGTH('dbo.ups_measurement', 'energy_storage_status_code') IS NULL ALTER TABLE dbo.ups_measurement ADD energy_storage_status_code int NULL;
    IF COL_LENGTH('dbo.ups_measurement', 'input_status_code') IS NULL ALTER TABLE dbo.ups_measurement ADD input_status_code int NULL;
    IF COL_LENGTH('dbo.ups_measurement', 'output_status_code') IS NULL ALTER TABLE dbo.ups_measurement ADD output_status_code int NULL;
    IF COL_LENGTH('dbo.ups_measurement', 'switchgear_status_code') IS NULL ALTER TABLE dbo.ups_measurement ADD switchgear_status_code int NULL;
    IF COL_LENGTH('dbo.ups_measurement', 'battery_breaker_status_code') IS NULL ALTER TABLE dbo.ups_measurement ADD battery_breaker_status_code int NULL;
END
GO

IF OBJECT_ID(N'dbo.ups_measurement', N'U') IS NOT NULL
BEGIN
    IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_ups_measurement_device_time' AND object_id = OBJECT_ID(N'dbo.ups_measurement'))
        DROP INDEX IX_ups_measurement_device_time ON dbo.ups_measurement;
    IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_ups_measurement_time' AND object_id = OBJECT_ID(N'dbo.ups_measurement'))
        DROP INDEX IX_ups_measurement_time ON dbo.ups_measurement;

    ALTER TABLE dbo.ups_measurement ALTER COLUMN measured_at datetime2(3) NOT NULL;
    ALTER TABLE dbo.ups_measurement ALTER COLUMN created_at datetime2(3) NOT NULL;
END
GO

IF OBJECT_ID(N'dbo.ups_measurement', N'U') IS NOT NULL
BEGIN
    IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_ups_measurement_device_time' AND object_id = OBJECT_ID(N'dbo.ups_measurement'))
        CREATE INDEX IX_ups_measurement_device_time ON dbo.ups_measurement(ups_id, measured_at DESC);
    IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_ups_measurement_time' AND object_id = OBJECT_ID(N'dbo.ups_measurement'))
        CREATE INDEX IX_ups_measurement_time ON dbo.ups_measurement(measured_at DESC);
END
GO

IF OBJECT_ID(N'dbo.ups_comm_status', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.ups_comm_status (
        ups_id int NOT NULL CONSTRAINT PK_ups_comm_status PRIMARY KEY,
        status varchar(20) NOT NULL,
        consecutive_fail_count int NOT NULL CONSTRAINT DF_ups_comm_status_fail_count DEFAULT (0),
        last_poll_at datetime2(3) NULL,
        last_success_at datetime2(3) NULL,
        last_error_at datetime2(3) NULL,
        last_error_message nvarchar(500) NULL,
        updated_at datetime2(3) NOT NULL CONSTRAINT DF_ups_comm_status_updated_at DEFAULT (sysdatetime()),
        CONSTRAINT FK_ups_comm_status_device FOREIGN KEY (ups_id) REFERENCES dbo.ups_device(ups_id)
    );
END
GO

IF OBJECT_ID(N'dbo.ups_comm_status', N'U') IS NOT NULL
BEGIN
    ALTER TABLE dbo.ups_comm_status ALTER COLUMN last_poll_at datetime2(3) NULL;
    ALTER TABLE dbo.ups_comm_status ALTER COLUMN last_success_at datetime2(3) NULL;
    ALTER TABLE dbo.ups_comm_status ALTER COLUMN last_error_at datetime2(3) NULL;
    ALTER TABLE dbo.ups_comm_status ALTER COLUMN updated_at datetime2(3) NOT NULL;
END
GO

IF OBJECT_ID(N'dbo.ups_alarm_rule', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.ups_alarm_rule (
        rule_id int IDENTITY(1,1) NOT NULL CONSTRAINT PK_ups_alarm_rule PRIMARY KEY,
        rule_code varchar(80) NOT NULL,
        metric_key varchar(80) NOT NULL,
        operator varchar(10) NOT NULL,
        threshold_value decimal(18,6) NOT NULL,
        severity varchar(20) NOT NULL,
        enabled bit NOT NULL CONSTRAINT DF_ups_alarm_rule_enabled DEFAULT (1),
        message_template nvarchar(300) NOT NULL,
        created_at datetime2(0) NOT NULL CONSTRAINT DF_ups_alarm_rule_created_at DEFAULT (sysdatetime()),
        updated_at datetime2(0) NOT NULL CONSTRAINT DF_ups_alarm_rule_updated_at DEFAULT (sysdatetime())
    );

    CREATE UNIQUE INDEX UX_ups_alarm_rule_code ON dbo.ups_alarm_rule(rule_code);
END
GO

IF OBJECT_ID(N'dbo.ups_alarm_log', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.ups_alarm_log (
        alarm_id bigint IDENTITY(1,1) NOT NULL CONSTRAINT PK_ups_alarm_log PRIMARY KEY,
        ups_id int NOT NULL,
        rule_code varchar(80) NULL,
        metric_key varchar(80) NULL,
        severity varchar(20) NOT NULL,
        alarm_message nvarchar(500) NOT NULL,
        occurred_at datetime2(0) NOT NULL,
        cleared_at datetime2(0) NULL,
        status varchar(20) NOT NULL CONSTRAINT DF_ups_alarm_log_status DEFAULT ('ACTIVE'),
        created_at datetime2(0) NOT NULL CONSTRAINT DF_ups_alarm_log_created_at DEFAULT (sysdatetime()),
        CONSTRAINT FK_ups_alarm_log_device FOREIGN KEY (ups_id) REFERENCES dbo.ups_device(ups_id)
    );

    CREATE INDEX IX_ups_alarm_log_active ON dbo.ups_alarm_log(status, occurred_at DESC);
END
GO

IF OBJECT_ID(N'dbo.ups_alarm_log', N'U') IS NOT NULL
BEGIN
    IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_ups_alarm_log_active' AND object_id = OBJECT_ID(N'dbo.ups_alarm_log'))
        CREATE INDEX IX_ups_alarm_log_active ON dbo.ups_alarm_log(status, occurred_at DESC);
    IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_ups_alarm_log_device_time' AND object_id = OBJECT_ID(N'dbo.ups_alarm_log'))
        CREATE INDEX IX_ups_alarm_log_device_time ON dbo.ups_alarm_log(ups_id, occurred_at DESC);
    IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_ups_alarm_log_rule_active' AND object_id = OBJECT_ID(N'dbo.ups_alarm_log'))
        CREATE INDEX IX_ups_alarm_log_rule_active ON dbo.ups_alarm_log(ups_id, rule_code, status);
END
GO

IF NOT EXISTS (SELECT 1 FROM dbo.ups_alarm_rule WHERE rule_code = 'UPS_STATUS_WORD_ACTIVE')
BEGIN
    INSERT INTO dbo.ups_alarm_rule (rule_code, metric_key, operator, threshold_value, severity, message_template)
    VALUES
        ('UPS_STATUS_WORD_ACTIVE', 'ups_status_word', '<>', 0, 'CRITICAL', N'UPS 상태 워드 알람 발생: 값 {value}'),
        ('ENERGY_STORAGE_STATUS_ACTIVE', 'energy_storage_status', '<>', 0, 'WARNING', N'에너지 저장장치 상태 알람 발생: 값 {value}'),
        ('GENERAL_STATUS_ACTIVE', 'general_status', '<>', 0, 'WARNING', N'일반 상태 알람 발생: 값 {value}'),
        ('INPUT_STATUS_ACTIVE', 'input_status', '<>', 0, 'WARNING', N'입력 상태 알람 발생: 값 {value}'),
        ('OUTPUT_STATUS_ACTIVE', 'output_status', '<>', 0, 'CRITICAL', N'출력 상태 알람 발생: 값 {value}'),
        ('SWITCHGEAR_STATUS_ACTIVE', 'switchgear_status', '<>', 0, 'WARNING', N'스위치기어 상태 알람 발생: 값 {value}'),
        ('BATTERY_HEALTH_ABNORMAL', 'battery_health_status', '<>', 0, 'WARNING', N'배터리 상태 이상: 값 {value}'),
        ('BATTERY_LOW', 'battery_charge_percent', '<=', 20, 'WARNING', N'배터리 충전율 낮음(20% 이하): {value}%'),
        ('BATTERY_CRITICAL', 'battery_charge_percent', '<=', 10, 'CRITICAL', N'배터리 충전율 위험(10% 이하): {value}%'),
        ('OUTPUT_LOAD_HIGH', 'output_load_total_percent', '>=', 80, 'WARNING', N'UPS 출력 부하율 높음(80% 이상): {value}%'),
        ('OUTPUT_LOAD_CRITICAL', 'output_load_total_percent', '>=', 95, 'CRITICAL', N'UPS 출력 과부하 위험(95% 이상): {value}%'),
        ('BATTERY_TEMP_HIGH', 'battery_temperature', '>=', 40, 'WARNING', N'배터리 온도 높음: {value}℃');
END
GO

UPDATE dbo.ups_alarm_rule
SET threshold_value = 1,
    updated_at = sysdatetime()
WHERE rule_code = 'BATTERY_HEALTH_ABNORMAL';
GO

UPDATE dbo.ups_alarm_rule
SET enabled = 0,
    updated_at = sysdatetime()
WHERE rule_code IN (
    'UPS_STATUS_WORD_ACTIVE',
    'ENERGY_STORAGE_STATUS_ACTIVE',
    'GENERAL_STATUS_ACTIVE',
    'INPUT_STATUS_ACTIVE',
    'OUTPUT_STATUS_ACTIVE',
    'SWITCHGEAR_STATUS_ACTIVE'
);
GO

IF NOT EXISTS (SELECT 1 FROM dbo.ups_alarm_rule WHERE rule_code = 'UPS_ON_BATTERY')
BEGIN
    INSERT INTO dbo.ups_alarm_rule (rule_code, metric_key, operator, threshold_value, severity, message_template)
    VALUES
        ('UPS_ON_BATTERY', 'ups_status_word', 'BIT_SET', 0, 'WARNING', N'UPS 배터리 운전 중'),
        ('UPS_MIN_RUNTIME', 'ups_status_word', 'BIT_SET', 1, 'CRITICAL', N'배터리 런타임이 최소 허용 시간보다 낮음'),
        ('UPS_IN_BYPASS', 'ups_status_word', 'BIT_SET', 2, 'WARNING', N'UPS 바이패스 운전 중'),
        ('UPS_BATTERY_TEST', 'ups_status_word', 'BIT_SET', 3, 'INFO', N'UPS 배터리 테스트 진행 중'),
        ('UPS_BATTERY_INOPERABLE', 'ups_status_word', 'BIT_SET', 9, 'CRITICAL', N'배터리 사용 불가 상태'),
        ('UPS_INFO_ALARM_PRESENT', 'ups_status_word', 'BIT_SET', 13, 'INFO', N'UPS 정보 알람 존재'),
        ('UPS_WARNING_ALARM_PRESENT', 'ups_status_word', 'BIT_SET', 14, 'WARNING', N'UPS 경고 알람 존재'),
        ('UPS_CRITICAL_ALARM_PRESENT', 'ups_status_word', 'BIT_SET', 15, 'CRITICAL', N'UPS 중요 알람 존재'),

        ('ENERGY_BB1_OPEN', 'energy_storage_status', 'BIT_SET', 0, 'WARNING', N'배터리 차단기 BB1 열림'),
        ('ENERGY_BB2_OPEN', 'energy_storage_status', 'BIT_SET', 1, 'WARNING', N'배터리 차단기 BB2 열림'),
        ('ENERGY_BB3_OPEN', 'energy_storage_status', 'BIT_SET', 2, 'WARNING', N'배터리 차단기 BB3 열림'),
        ('ENERGY_BB4_OPEN', 'energy_storage_status', 'BIT_SET', 3, 'WARNING', N'배터리 차단기 BB4 열림'),
        ('ENERGY_DISCHARGING', 'energy_storage_status', 'BIT_SET', 4, 'WARNING', N'배터리 방전 중'),
        ('ENERGY_CHARGER_HIGH_TEMP_SHUTDOWN', 'energy_storage_status', 'BIT_SET', 5, 'CRITICAL', N'고온으로 충전기 정지'),
        ('ENERGY_MIN_RUNTIME', 'energy_storage_status', 'BIT_SET', 6, 'CRITICAL', N'배터리 런타임 부족'),
        ('ENERGY_BATTERY_VOLTAGE_MISMATCH', 'energy_storage_status', 'BIT_SET', 7, 'CRITICAL', N'배터리 전압과 설정 불일치'),
        ('ENERGY_BATTERY_WEAK', 'energy_storage_status', 'BIT_SET', 8, 'WARNING', N'배터리 상태 약화'),
        ('ENERGY_BATTERY_POOR', 'energy_storage_status', 'BIT_SET', 9, 'CRITICAL', N'배터리 상태 불량'),
        ('ENERGY_BATTERY_TEMP_HIGH', 'energy_storage_status', 'BIT_SET', 10, 'WARNING', N'배터리 고온 상태'),
        ('ENERGY_BATTERY_TEMP_LOW', 'energy_storage_status', 'BIT_SET', 11, 'WARNING', N'배터리 저온 상태'),
        ('ENERGY_BATTERY_CAPACITY_LOW', 'energy_storage_status', 'BIT_SET', 12, 'WARNING', N'배터리 용량 부족'),
        ('ENERGY_CHARGE_POWER_REDUCED', 'energy_storage_status', 'BIT_SET', 13, 'WARNING', N'배터리 충전 전력 제한'),
        ('ENERGY_BATTERY_NOT_WORKING', 'energy_storage_status', 'BIT_SET', 14, 'CRITICAL', N'배터리 동작 이상'),
        ('ENERGY_FLOAT_CURRENT_HIGH', 'energy_storage_status', 'BIT_SET', 15, 'WARNING', N'배터리 부동 충전 전류 초과'),

        ('GENERAL_EPO_ACTIVE', 'general_status', 'BIT_SET', 0, 'CRITICAL', N'EPO 스위치 동작'),
        ('GENERAL_SYNC_UNAVAILABLE', 'general_status', 'BIT_SET', 1, 'WARNING', N'동기화 불가, 프리런 운전'),
        ('GENERAL_INVERTER_BYPASS_PHASE_MISMATCH', 'general_status', 'BIT_SET', 2, 'CRITICAL', N'인버터 출력과 바이패스 입력 위상 불일치'),
        ('GENERAL_SYSTEM_LOCKED_BYPASS', 'general_status_2', 'BIT_SET', 9, 'CRITICAL', N'시스템이 바이패스 운전에 고정됨'),
        ('GENERAL_UNSUPPORTED_POWER_MODULE', 'general_status_2', 'BIT_SET', 11, 'CRITICAL', N'지원하지 않는 파워 모듈 감지'),
        ('GENERAL_UNSUPPORTED_SBS', 'general_status_2', 'BIT_SET', 12, 'CRITICAL', N'지원하지 않는 정적 바이패스 스위치 모듈 감지'),
        ('GENERAL_RATING_EXCEEDS_FRAME', 'general_status_2', 'BIT_SET', 14, 'CRITICAL', N'설정된 UPS 정격이 프레임 용량을 초과'),
        ('GENERAL_NO_SBS', 'general_status_3', 'BIT_SET', 1, 'WARNING', N'정적 바이패스 스위치 모듈 없음'),
        ('GENERAL_NO_POWER_MODULE', 'general_status_3', 'BIT_SET', 2, 'CRITICAL', N'파워 모듈 없음'),
        ('GENERAL_AMBIENT_TEMP_OUT', 'general_status_3', 'BIT_SET', 5, 'WARNING', N'주변 온도 허용 범위 이탈'),
        ('GENERAL_AMBIENT_TEMP_HIGH', 'general_status_3', 'BIT_SET', 6, 'WARNING', N'주변 온도 높음'),
        ('GENERAL_WARRANTY_EXPIRING', 'general_status_3', 'BIT_SET', 9, 'INFO', N'보증 만료 임박'),
        ('GENERAL_TECH_CHECK', 'general_status_3', 'BIT_SET', 10, 'INFO', N'기술 점검 권장'),
        ('GENERAL_AIR_FILTER_CHECK', 'general_status_3', 'BIT_SET', 11, 'INFO', N'에어 필터 기술 점검 권장'),
        ('GENERAL_SURVEILLANCE_FAULT', 'general_status_3', 'BIT_SET', 13, 'CRITICAL', N'UPS 감시 기능에서 고장 감지'),
        ('GENERAL_DISPLAY_COMM_LOST', 'general_status_3', 'BIT_SET', 14, 'WARNING', N'디스플레이 통신 끊김'),
        ('GENERAL_DISPLAY_NOT_AUTH', 'general_status_4', 'BIT_SET', 0, 'WARNING', N'디스플레이 통신 인증 실패'),
        ('GENERAL_MODEL_INCORRECT', 'general_status_4', 'BIT_SET', 4, 'CRITICAL', N'잘못된 UPS 모델 번호 감지'),
        ('GENERAL_PM_REDUNDANCY_LOST', 'general_status_4', 'BIT_SET', 7, 'WARNING', N'내부 파워 모듈 이중화 상실'),
        ('GENERAL_PM_ID_CONFIG_NOT_OK', 'general_status_4', 'BIT_SET', 10, 'WARNING', N'파워 모듈 ID 설정 이상'),
        ('GENERAL_DCDC_LIMIT_HIGH_TEMP', 'general_status_4', 'BIT_SET', 11, 'WARNING', N'고온으로 DC-DC 전류 제한 임계값 낮아짐'),
        ('GENERAL_PFC_LIMIT_HIGH_TEMP', 'general_status_4', 'BIT_SET', 13, 'WARNING', N'고온으로 PFC AC 전류 제한 임계값 낮아짐'),

        ('BYPASS_VOLTAGE_OUT', 'bypass_status', 'BIT_SET', 0, 'WARNING', N'바이패스 전압 허용 범위 이탈'),
        ('BYPASS_PHASE_SEQUENCE', 'bypass_status', 'BIT_SET', 1, 'WARNING', N'바이패스 상 회전 순서 이상'),
        ('BYPASS_FREQ_OUT', 'bypass_status', 'BIT_SET', 2, 'WARNING', N'바이패스 주파수 허용 범위 이탈'),
        ('BYPASS_PHASE_MISSING', 'bypass_status', 'BIT_SET', 3, 'WARNING', N'바이패스 결상'),

        ('ENERGY_HIGH_TEMP_SHUTDOWN', 'energy_storage_status_2', 'BIT_SET', 0, 'CRITICAL', N'배터리 고온으로 시스템 정지'),
        ('ENERGY_CONFIG_INCORRECT', 'energy_storage_status_2', 'BIT_SET', 1, 'CRITICAL', N'배터리 설정 오류'),
        ('ENERGY_LOW_TEMP_CHARGER_SHUTDOWN', 'energy_storage_status_2', 'BIT_SET', 2, 'CRITICAL', N'저온으로 충전기 정지'),

        ('INPUT_VOLTAGE_OUT', 'input_status', 'BIT_SET', 0, 'CRITICAL', N'입력 전압 허용 범위 이탈'),
        ('INPUT_PHASE_SEQUENCE', 'input_status', 'BIT_SET', 1, 'CRITICAL', N'입력 상 회전 순서 이상'),
        ('INPUT_FREQ_OUT', 'input_status', 'BIT_SET', 2, 'CRITICAL', N'입력 주파수 허용 범위 이탈'),
        ('INPUT_PHASE_MISSING', 'input_status', 'BIT_SET', 3, 'CRITICAL', N'입력 결상'),
        ('INPUT_NEUTRAL_DISPLACEMENT', 'input_status', 'BIT_SET', 9, 'WARNING', N'입력 중성점 변위 감지'),

        ('OUTPUT_VOLTAGE_OUT', 'output_status', 'BIT_SET', 0, 'CRITICAL', N'출력 전압 허용 범위 이탈'),
        ('OUTPUT_FREQ_OUT', 'output_status', 'BIT_SET', 1, 'CRITICAL', N'출력 주파수 허용 범위 이탈'),
        ('OUTPUT_OVERLOAD_SHORT', 'output_status', 'BIT_SET', 2, 'CRITICAL', N'UPS 과부하 또는 단락'),
        ('OUTPUT_OVERLOAD_HIGH_AMBIENT', 'output_status', 'BIT_SET', 3, 'CRITICAL', N'고온으로 인한 UPS 과부하'),
        ('OUTPUT_LOAD_WARNING', 'output_status', 'BIT_SET', 5, 'WARNING', N'UPS 부하 경고 레벨 초과'),

        ('PARALLEL_PBUS1_LOST', 'parallel_status', 'BIT_SET', 0, 'WARNING', N'병렬 PBUS 케이블 1 통신 끊김'),
        ('PARALLEL_PBUS2_LOST', 'parallel_status', 'BIT_SET', 1, 'WARNING', N'병렬 PBUS 케이블 2 통신 끊김'),
        ('PARALLEL_GENERAL_EVENT', 'parallel_status', 'BIT_SET', 2, 'WARNING', N'병렬 시스템 설정 또는 동작 이상'),
        ('PARALLEL_UNIT_NOT_PRESENT', 'parallel_status', 'BIT_SET', 4, 'WARNING', N'병렬 UPS 유닛 통신 불가'),
        ('PARALLEL_REDUNDANCY_LOST', 'parallel_status', 'BIT_SET', 5, 'CRITICAL', N'병렬 이중화 상실'),
        ('PARALLEL_NOT_ENOUGH_READY', 'parallel_status', 'BIT_SET', 6, 'WARNING', N'인버터 투입 준비 UPS 수 부족'),

        ('POWER_MODULE_INOPERABLE', 'power_module_status', 'BIT_SET', 0, 'CRITICAL', N'파워 모듈 사용 불가'),
        ('POWER_MODULE_TEMP_WARNING', 'power_module_status', 'BIT_SET', 1, 'WARNING', N'파워 모듈 온도 경고'),
        ('POWER_MODULE_OVERHEATED', 'power_module_status', 'BIT_SET', 2, 'CRITICAL', N'파워 모듈 과열'),
        ('POWER_MODULE_FAN_INOPERABLE', 'power_module_status', 'BIT_SET', 7, 'CRITICAL', N'파워 모듈 팬 동작 이상'),
        ('POWER_MODULE_DISABLED', 'power_module_status', 'BIT_SET', 8, 'WARNING', N'파워 모듈 비활성'),
        ('POWER_MODULE_SURVEILLANCE_FAULT', 'power_module_status', 'BIT_SET', 9, 'CRITICAL', N'파워 모듈 감시 기능에서 고장 감지'),
        ('POWER_MODULE_PMC_LOST_DISCONNECTED', 'power_module_status', 'BIT_SET', 10, 'CRITICAL', N'PMC 통신 끊김'),
        ('POWER_MODULE_PMC_LOST_CONNECTED', 'power_module_status', 'BIT_SET', 11, 'WARNING', N'PMC 통신 이상'),
        ('POWER_MODULE_PMC_NOT_AUTH', 'power_module_status', 'BIT_SET', 12, 'WARNING', N'PMC 통신 인증 실패');
END
GO

UPDATE dbo.ups_alarm_rule
SET enabled = 0,
    updated_at = sysdatetime()
WHERE rule_code IN (
    'UPS_INFO_ALARM_PRESENT',
    'UPS_WARNING_ALARM_PRESENT',
    'UPS_CRITICAL_ALARM_PRESENT'
);
GO

UPDATE dbo.ups_alarm_rule SET metric_key = 'general_status_2', updated_at = sysdatetime()
WHERE rule_code IN (
    'GENERAL_SYSTEM_LOCKED_BYPASS',
    'GENERAL_UNSUPPORTED_POWER_MODULE',
    'GENERAL_UNSUPPORTED_SBS',
    'GENERAL_RATING_EXCEEDS_FRAME'
);
GO

IF NOT EXISTS (SELECT 1 FROM dbo.ups_modbus_profile WHERE profile_name = N'Generic Modbus UPS')
BEGIN
    INSERT INTO dbo.ups_modbus_profile (profile_name, vendor_name, model_name, note)
    VALUES (N'Generic Modbus UPS', N'Generic', N'Modbus TCP', N'기본 UPS Modbus TCP 프로파일입니다. 실제 장비 매뉴얼에 맞게 주소를 조정하세요.');
END
GO

DECLARE @profile_id int = (SELECT TOP 1 profile_id FROM dbo.ups_modbus_profile WHERE profile_name = N'Generic Modbus UPS');

IF @profile_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.ups_modbus_point WHERE profile_id = @profile_id)
BEGIN
    INSERT INTO dbo.ups_modbus_point
        (profile_id, metric_key, display_name, function_code, register_address, data_type, scale_factor, unit, sort_order)
    VALUES
        (@profile_id, 'input_voltage', N'입력 전압', 4, 30001, 'UINT16', 0.1, N'V', 10),
        (@profile_id, 'output_voltage', N'출력 전압', 4, 30002, 'UINT16', 0.1, N'V', 20),
        (@profile_id, 'output_current', N'출력 전류', 4, 30003, 'UINT16', 0.1, N'A', 30),
        (@profile_id, 'output_power_kw', N'출력 전력', 4, 30004, 'UINT16', 0.1, N'kW', 40),
        (@profile_id, 'load_percent', N'부하율', 4, 30005, 'UINT16', 1, N'%', 50),
        (@profile_id, 'frequency', N'주파수', 4, 30006, 'UINT16', 0.1, N'Hz', 60),
        (@profile_id, 'battery_voltage', N'배터리 전압', 4, 30007, 'UINT16', 0.1, N'V', 70),
        (@profile_id, 'battery_charge_percent', N'배터리 충전율', 4, 30008, 'UINT16', 1, N'%', 80),
        (@profile_id, 'battery_temperature', N'배터리 온도', 4, 30009, 'INT16', 0.1, N'℃', 90),
        (@profile_id, 'remaining_minutes', N'잔여 시간', 4, 30010, 'UINT16', 1, N'min', 100),
        (@profile_id, 'raw_status', N'상태 코드', 4, 30011, 'UINT16', 1, NULL, 110);
END
GO

IF NOT EXISTS (SELECT 1 FROM dbo.ups_modbus_profile WHERE profile_name = N'Schneider Easy UPS 3-Phase Modular')
BEGIN
    INSERT INTO dbo.ups_modbus_profile
        (profile_name, vendor_name, model_name, byte_order, word_order, note)
    VALUES
        (
            N'Schneider Easy UPS 3-Phase Modular',
            N'Schneider Electric',
            N'Easy UPS 3-Phase Modular / Galaxy PX map',
            'BIG_ENDIAN',
            'HIGH_WORD_FIRST',
            N'Modbus Register Map JEDI_Easy UPS 3-Phase Modular v1.7 기준. 상세 포인트는 ups/scripts/create_schneider_easy_ups_profile.sql에서 관리합니다.'
        );
END
GO
