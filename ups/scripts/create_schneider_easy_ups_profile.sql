USE UPS_MONITOR;
GO

DECLARE @profile_id int;

IF NOT EXISTS (
    SELECT 1
    FROM dbo.ups_modbus_profile
    WHERE profile_name = N'Schneider Easy UPS 3-Phase Modular'
)
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
            N'Modbus Register Map JEDI_Easy UPS 3-Phase Modular v1.7 기준. register_address는 PDF의 Absolute Starting Register Address(Decimal)를 사용합니다.'
        );
END

SELECT @profile_id = profile_id
FROM dbo.ups_modbus_profile
WHERE profile_name = N'Schneider Easy UPS 3-Phase Modular';

DELETE FROM dbo.ups_modbus_point
WHERE profile_id = @profile_id;

INSERT INTO dbo.ups_modbus_point
    (profile_id, metric_key, display_name, function_code, register_address, register_count, data_type, scale_factor, unit, sort_order)
VALUES
    (@profile_id, 'ups_status_word', N'UPS Status', 4, 1, 1, 'UINT16', 1, NULL, 10),
    (@profile_id, 'bypass_status', N'Bypass Status', 4, 2, 1, 'UINT16', 1, NULL, 15),
    (@profile_id, 'energy_storage_status', N'Energy Storage Status 1', 4, 3, 1, 'UINT16', 1, NULL, 20),
    (@profile_id, 'energy_storage_status_2', N'Energy Storage Status 2', 4, 4, 1, 'UINT16', 1, NULL, 25),
    (@profile_id, 'general_status', N'General Status 1', 4, 5, 1, 'UINT16', 1, NULL, 30),
    (@profile_id, 'general_status_2', N'General Status 2', 4, 6, 1, 'UINT16', 1, NULL, 35),
    (@profile_id, 'general_status_3', N'General Status 3', 4, 7, 1, 'UINT16', 1, NULL, 36),
    (@profile_id, 'general_status_4', N'General Status 4', 4, 8, 1, 'UINT16', 1, NULL, 37),
    (@profile_id, 'input_status', N'Input Status', 4, 11, 1, 'UINT16', 1, NULL, 40),
    (@profile_id, 'output_status', N'Output Status', 4, 12, 1, 'UINT16', 1, NULL, 50),
    (@profile_id, 'parallel_status', N'Parallel System Status', 4, 13, 1, 'UINT16', 1, NULL, 55),
    (@profile_id, 'power_module_status', N'Power Module Status', 4, 14, 1, 'UINT16', 1, NULL, 56),
    (@profile_id, 'switchgear_status', N'Switchgear Status', 4, 17, 1, 'UINT16', 1, NULL, 60),

    (@profile_id, 'input_frequency', N'입력 주파수', 4, 4096, 1, 'UINT16', 0.1, N'Hz', 100),
    (@profile_id, 'input_voltage_l1n', N'입력 전압 L1-N', 4, 4097, 1, 'UINT16', 1, N'V', 110),
    (@profile_id, 'input_voltage_l2n', N'입력 전압 L2-N', 4, 4098, 1, 'UINT16', 1, N'V', 120),
    (@profile_id, 'input_voltage_l3n', N'입력 전압 L3-N', 4, 4099, 1, 'UINT16', 1, N'V', 130),
    (@profile_id, 'input_voltage_l12', N'입력 전압 L1-L2', 4, 4100, 1, 'UINT16', 1, N'V', 140),
    (@profile_id, 'input_voltage_l23', N'입력 전압 L2-L3', 4, 4101, 1, 'UINT16', 1, N'V', 150),
    (@profile_id, 'input_voltage_l31', N'입력 전압 L3-L1', 4, 4102, 1, 'UINT16', 1, N'V', 160),
    (@profile_id, 'input_current_l1', N'입력 전류 L1', 4, 4103, 1, 'UINT16', 1, N'A', 170),
    (@profile_id, 'input_current_l2', N'입력 전류 L2', 4, 4104, 1, 'UINT16', 1, N'A', 180),
    (@profile_id, 'input_current_l3', N'입력 전류 L3', 4, 4105, 1, 'UINT16', 1, N'A', 190),
    (@profile_id, 'input_power_l1_kw', N'입력 유효전력 L1', 4, 4106, 1, 'UINT16', 1, N'kW', 200),
    (@profile_id, 'input_power_l2_kw', N'입력 유효전력 L2', 4, 4107, 1, 'UINT16', 1, N'kW', 210),
    (@profile_id, 'input_power_l3_kw', N'입력 유효전력 L3', 4, 4108, 1, 'UINT16', 1, N'kW', 220),
    (@profile_id, 'input_power_total_kw', N'입력 총 유효전력', 4, 4115, 1, 'UINT16', 1, N'kW', 230),
    (@profile_id, 'input_apparent_total_kva', N'입력 총 피상전력', 4, 4116, 1, 'UINT16', 1, N'kVA', 240),

    (@profile_id, 'bypass_frequency', N'바이패스 주파수', 4, 4352, 1, 'UINT16', 0.1, N'Hz', 300),
    (@profile_id, 'bypass_voltage_l1n', N'바이패스 전압 L1-N', 4, 4353, 1, 'UINT16', 1, N'V', 310),
    (@profile_id, 'bypass_voltage_l2n', N'바이패스 전압 L2-N', 4, 4354, 1, 'UINT16', 1, N'V', 320),
    (@profile_id, 'bypass_voltage_l3n', N'바이패스 전압 L3-N', 4, 4355, 1, 'UINT16', 1, N'V', 330),
    (@profile_id, 'bypass_power_total_kw', N'바이패스 총 유효전력', 4, 4371, 1, 'UINT16', 1, N'kW', 340),

    (@profile_id, 'output_frequency', N'출력 주파수', 4, 4608, 1, 'UINT16', 0.1, N'Hz', 400),
    (@profile_id, 'output_voltage_l1n', N'출력 전압 L1-N', 4, 4609, 1, 'UINT16', 1, N'V', 410),
    (@profile_id, 'output_voltage_l2n', N'출력 전압 L2-N', 4, 4610, 1, 'UINT16', 1, N'V', 420),
    (@profile_id, 'output_voltage_l3n', N'출력 전압 L3-N', 4, 4611, 1, 'UINT16', 1, N'V', 430),
    (@profile_id, 'output_voltage_l12', N'출력 전압 L1-L2', 4, 4612, 1, 'UINT16', 1, N'V', 440),
    (@profile_id, 'output_voltage_l23', N'출력 전압 L2-L3', 4, 4613, 1, 'UINT16', 1, N'V', 450),
    (@profile_id, 'output_voltage_l31', N'출력 전압 L3-L1', 4, 4614, 1, 'UINT16', 1, N'V', 460),
    (@profile_id, 'output_current_l1', N'출력 전류 L1', 4, 4615, 1, 'UINT16', 1, N'A', 470),
    (@profile_id, 'output_current_l2', N'출력 전류 L2', 4, 4616, 1, 'UINT16', 1, N'A', 480),
    (@profile_id, 'output_current_l3', N'출력 전류 L3', 4, 4617, 1, 'UINT16', 1, N'A', 490),
    (@profile_id, 'output_power_l1_kw', N'출력 유효전력 L1', 4, 4618, 1, 'UINT16', 1, N'kW', 500),
    (@profile_id, 'output_power_l2_kw', N'출력 유효전력 L2', 4, 4619, 1, 'UINT16', 1, N'kW', 510),
    (@profile_id, 'output_power_l3_kw', N'출력 유효전력 L3', 4, 4620, 1, 'UINT16', 1, N'kW', 520),
    (@profile_id, 'output_load_l1_percent', N'출력 부하율 L1', 4, 4624, 1, 'UINT16', 0.1, N'%', 530),
    (@profile_id, 'output_load_l2_percent', N'출력 부하율 L2', 4, 4625, 1, 'UINT16', 0.1, N'%', 540),
    (@profile_id, 'output_load_l3_percent', N'출력 부하율 L3', 4, 4626, 1, 'UINT16', 0.1, N'%', 550),
    (@profile_id, 'output_power_total_kw', N'출력 총 유효전력', 4, 4627, 1, 'UINT16', 1, N'kW', 560),
    (@profile_id, 'output_apparent_l1_kva', N'출력 피상전력 L1', 4, 4621, 1, 'UINT16', 1, N'kVA', 585),
    (@profile_id, 'output_apparent_l2_kva', N'출력 피상전력 L2', 4, 4622, 1, 'UINT16', 1, N'kVA', 586),
    (@profile_id, 'output_apparent_l3_kva', N'출력 피상전력 L3', 4, 4623, 1, 'UINT16', 1, N'kVA', 587),
    (@profile_id, 'output_pf_l1', N'출력 역률 L1', 4, 4628, 1, 'UINT16', 0.01, NULL, 570),
    (@profile_id, 'output_pf_l2', N'출력 역률 L2', 4, 4629, 1, 'UINT16', 0.01, NULL, 580),
    (@profile_id, 'output_pf_l3', N'출력 역률 L3', 4, 4630, 1, 'UINT16', 0.01, NULL, 590),
    (@profile_id, 'output_apparent_total_kva', N'출력 총 피상전력', 4, 4631, 1, 'UINT16', 1, N'kVA', 600),
    (@profile_id, 'output_load_total_percent', N'출력 총 부하율', 4, 4632, 1, 'UINT16', 0.1, N'%', 610),

    (@profile_id, 'battery_temperature', N'배터리 최고 온도', 4, 4864, 1, 'UINT16', 0.1, N'℃', 700),
    (@profile_id, 'battery_voltage', N'배터리 전압', 4, 4865, 1, 'UINT16', 1, N'V', 710),
    (@profile_id, 'battery_current', N'배터리 전류', 4, 4866, 2, 'INT32', 1, N'A', 720),
    (@profile_id, 'battery_power_kw', N'배터리 전력', 4, 4868, 1, 'UINT16', 1, N'kW', 730),
    (@profile_id, 'battery_recharge_seconds', N'배터리 재충전 예상 시간', 4, 4869, 1, 'UINT32', 1, N's', 740),
    (@profile_id, 'battery_charge_percent', N'배터리 충전율', 4, 4871, 1, 'UINT16', 1, N'%', 750),
    (@profile_id, 'battery_remaining_seconds', N'저전압 차단까지 잔여 시간', 4, 4872, 2, 'UINT32', 1, N's', 760),
    (@profile_id, 'charger_operation_mode', N'충전기 운전 모드', 4, 4874, 1, 'ENUM', 1, NULL, 770),
    (@profile_id, 'charger_condition', N'충전기 상태', 4, 4875, 1, 'ENUM', 1, NULL, 780),
    (@profile_id, 'battery_breaker_status', N'배터리 차단기 상태', 4, 4876, 1, 'ENUM', 1, NULL, 790),
    (@profile_id, 'battery_health_status', N'배터리 상태', 4, 4880, 1, 'ENUM', 1, NULL, 800),
    (@profile_id, 'battery_capacity_ah', N'배터리 가용 용량', 4, 4881, 1, 'UINT16', 1, N'Ah', 810),

    (@profile_id, 'parallel_output_apparent_kva', N'병렬 시스템 출력 피상전력', 4, 4902, 1, 'UINT16', 1, N'kVA', 900),
    (@profile_id, 'parallel_load_percent', N'병렬 시스템 부하율', 4, 4903, 1, 'UINT16', 0.1, N'%', 910),
    (@profile_id, 'parallel_output_power_kw', N'병렬 시스템 출력 유효전력', 4, 4904, 1, 'UINT16', 1, N'kW', 920),

    (@profile_id, 'ambient_temperature', N'주변 온도', 4, 5376, 1, 'UINT16', 0.1, N'℃', 1000),
    (@profile_id, 'general_switchgear_status', N'스위치기어 상태', 4, 5377, 1, 'UINT16', 1, NULL, 1010),
    (@profile_id, 'ups_operation_mode', N'UPS 운전 모드', 4, 5378, 2, 'ENUM', 1, NULL, 1020),
    (@profile_id, 'system_operation_mode', N'시스템 운전 모드', 4, 5380, 1, 'ENUM', 1, NULL, 1030),
    (@profile_id, 'power_module_present_status', N'파워 모듈 장착 상태', 4, 5381, 1, 'UINT16', 1, NULL, 1040),
    (@profile_id, 'external_breaker_status', N'외부 차단기 상태', 4, 5382, 1, 'UINT16', 1, NULL, 1050),

    (@profile_id, 'ups_power_rating_kva', N'UPS 정격 용량', 4, 8201, 1, 'UINT16', 1, N'kVA', 1100),
    (@profile_id, 'output_overload_threshold', N'출력 과부하 임계값', 4, 8202, 1, 'UINT16', 1, N'%', 1110),
    (@profile_id, 'battery_type', N'배터리 타입', 4, 8210, 1, 'ENUM', 1, NULL, 1120);

SELECT @profile_id AS profile_id, COUNT(*) AS point_count
FROM dbo.ups_modbus_point
WHERE profile_id = @profile_id;
GO
