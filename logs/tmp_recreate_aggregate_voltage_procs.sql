CREATE OR ALTER PROCEDURE dbo.sp_aggregate_hourly_measurements
AS
BEGIN
    SET NOCOUNT ON;

    MERGE dbo.hourly_measurements AS t
    USING (
        SELECT
            m.meter_id,
            DATEADD(HOUR, DATEDIFF(HOUR, 0, m.measured_at), 0) AS measured_hour,
            AVG(m.average_current) AS avg_current,
            MAX(lv.row_max_line_voltage) AS max_line_voltage,
            MIN(lv.row_min_line_voltage) AS min_line_voltage,
            MAX(pv.row_max_phase_voltage) AS max_phase_voltage,
            MIN(pv.row_min_phase_voltage) AS min_phase_voltage,
            MAX(m.current_max) AS max_current,
            MIN(m.current_min) AS min_current,
            MAX(m.energy_consumed_total) - MIN(m.energy_consumed_total) AS energy_consumed_kwh,
            AVG(lv.row_avg_line_voltage) AS line_voltage_avg,
            AVG(pv.row_avg_phase_voltage) AS phase_voltage_avg,
            AVG(m.power_factor) AS power_factor,
            MAX(m.max_power) AS max_power,
            MAX(m.reactive_energy_total) - MIN(m.reactive_energy_total) AS reactive_energy_kvarh
        FROM dbo.measurements m
        OUTER APPLY (
            SELECT
                AVG(v) AS row_avg_line_voltage,
                MAX(v) AS row_max_line_voltage,
                MIN(v) AS row_min_line_voltage
            FROM (VALUES
                (CASE WHEN m.voltage_ab IS NULL OR ABS(m.voltage_ab) < 0.001 THEN NULL ELSE m.voltage_ab END),
                (CASE WHEN m.voltage_bc IS NULL OR ABS(m.voltage_bc) < 0.001 THEN NULL ELSE m.voltage_bc END),
                (CASE WHEN m.voltage_ca IS NULL OR ABS(m.voltage_ca) < 0.001 THEN NULL ELSE m.voltage_ca END)
            ) AS src(v)
        ) lv
        OUTER APPLY (
            SELECT
                AVG(v) AS row_avg_phase_voltage,
                MAX(v) AS row_max_phase_voltage,
                MIN(v) AS row_min_phase_voltage
            FROM (VALUES
                (CASE WHEN m.voltage_an IS NULL OR ABS(m.voltage_an) < 0.001 THEN NULL ELSE m.voltage_an END),
                (CASE WHEN m.voltage_bn IS NULL OR ABS(m.voltage_bn) < 0.001 THEN NULL ELSE m.voltage_bn END),
                (CASE WHEN m.voltage_cn IS NULL OR ABS(m.voltage_cn) < 0.001 THEN NULL ELSE m.voltage_cn END)
            ) AS src(v)
        ) pv
        WHERE m.measured_at >= DATEADD(DAY, -2, GETDATE())
        GROUP BY m.meter_id, DATEADD(HOUR, DATEDIFF(HOUR, 0, m.measured_at), 0)
    ) AS s
    ON (t.meter_id = s.meter_id AND t.measured_hour = s.measured_hour)
    WHEN MATCHED THEN
        UPDATE SET
            avg_current = s.avg_current,
            max_line_voltage = s.max_line_voltage,
            min_line_voltage = s.min_line_voltage,
            max_phase_voltage = s.max_phase_voltage,
            min_phase_voltage = s.min_phase_voltage,
            max_current = s.max_current,
            min_current = s.min_current,
            energy_consumed_kwh = s.energy_consumed_kwh,
            line_voltage_avg = s.line_voltage_avg,
            phase_voltage_avg = s.phase_voltage_avg,
            power_factor = s.power_factor,
            max_power = s.max_power,
            reactive_energy_kvarh = s.reactive_energy_kvarh
    WHEN NOT MATCHED THEN
        INSERT (
            meter_id, measured_hour, avg_current,
            max_line_voltage, min_line_voltage, max_phase_voltage, min_phase_voltage,
            max_current, min_current, energy_consumed_kwh,
            line_voltage_avg, phase_voltage_avg, power_factor, max_power, reactive_energy_kvarh
        )
        VALUES (
            s.meter_id, s.measured_hour, s.avg_current,
            s.max_line_voltage, s.min_line_voltage, s.max_phase_voltage, s.min_phase_voltage,
            s.max_current, s.min_current, s.energy_consumed_kwh,
            s.line_voltage_avg, s.phase_voltage_avg, s.power_factor, s.max_power, s.reactive_energy_kvarh
        );
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_aggregate_daily_measurements
AS
BEGIN
    SET NOCOUNT ON;

    MERGE dbo.daily_measurements AS t
    USING (
        SELECT
            m.meter_id,
            CAST(m.measured_at AS DATE) AS measured_date,
            AVG(m.average_current) AS avg_current,
            MAX(lv.row_max_line_voltage) AS max_line_voltage,
            MIN(lv.row_min_line_voltage) AS min_line_voltage,
            MAX(pv.row_max_phase_voltage) AS max_phase_voltage,
            MIN(pv.row_min_phase_voltage) AS min_phase_voltage,
            MAX(m.current_max) AS max_current,
            MIN(m.current_min) AS min_current,
            MAX(m.energy_consumed_total) - MIN(m.energy_consumed_total) AS energy_consumed_kwh,
            AVG(lv.row_avg_line_voltage) AS line_voltage_avg,
            AVG(pv.row_avg_phase_voltage) AS phase_voltage_avg,
            AVG(m.power_factor) AS power_factor,
            MAX(m.max_power) AS max_power,
            MAX(m.reactive_energy_total) - MIN(m.reactive_energy_total) AS reactive_energy_kvarh
        FROM dbo.measurements m
        OUTER APPLY (
            SELECT AVG(v) AS row_avg_line_voltage, MAX(v) AS row_max_line_voltage, MIN(v) AS row_min_line_voltage
            FROM (VALUES
                (CASE WHEN m.voltage_ab IS NULL OR ABS(m.voltage_ab) < 0.001 THEN NULL ELSE m.voltage_ab END),
                (CASE WHEN m.voltage_bc IS NULL OR ABS(m.voltage_bc) < 0.001 THEN NULL ELSE m.voltage_bc END),
                (CASE WHEN m.voltage_ca IS NULL OR ABS(m.voltage_ca) < 0.001 THEN NULL ELSE m.voltage_ca END)
            ) AS src(v)
        ) lv
        OUTER APPLY (
            SELECT AVG(v) AS row_avg_phase_voltage, MAX(v) AS row_max_phase_voltage, MIN(v) AS row_min_phase_voltage
            FROM (VALUES
                (CASE WHEN m.voltage_an IS NULL OR ABS(m.voltage_an) < 0.001 THEN NULL ELSE m.voltage_an END),
                (CASE WHEN m.voltage_bn IS NULL OR ABS(m.voltage_bn) < 0.001 THEN NULL ELSE m.voltage_bn END),
                (CASE WHEN m.voltage_cn IS NULL OR ABS(m.voltage_cn) < 0.001 THEN NULL ELSE m.voltage_cn END)
            ) AS src(v)
        ) pv
        WHERE m.measured_at >= DATEADD(DAY, -1, CAST(GETDATE() AS DATE))
        GROUP BY m.meter_id, CAST(m.measured_at AS DATE)
    ) AS s
    ON (t.meter_id = s.meter_id AND t.measured_date = s.measured_date)
    WHEN MATCHED THEN
        UPDATE SET
            avg_current = s.avg_current,
            max_line_voltage = s.max_line_voltage,
            min_line_voltage = s.min_line_voltage,
            max_phase_voltage = s.max_phase_voltage,
            min_phase_voltage = s.min_phase_voltage,
            max_current = s.max_current,
            min_current = s.min_current,
            energy_consumed_kwh = s.energy_consumed_kwh,
            line_voltage_avg = s.line_voltage_avg,
            phase_voltage_avg = s.phase_voltage_avg,
            power_factor = s.power_factor,
            max_power = s.max_power,
            reactive_energy_kvarh = s.reactive_energy_kvarh
    WHEN NOT MATCHED THEN
        INSERT (
            meter_id, measured_date, avg_current,
            max_line_voltage, min_line_voltage, max_phase_voltage, min_phase_voltage,
            max_current, min_current, energy_consumed_kwh,
            line_voltage_avg, phase_voltage_avg, power_factor, max_power, reactive_energy_kvarh
        )
        VALUES (
            s.meter_id, s.measured_date, s.avg_current,
            s.max_line_voltage, s.min_line_voltage, s.max_phase_voltage, s.min_phase_voltage,
            s.max_current, s.min_current, s.energy_consumed_kwh,
            s.line_voltage_avg, s.phase_voltage_avg, s.power_factor, s.max_power, s.reactive_energy_kvarh
        );
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_aggregate_monthly_measurements
AS
BEGIN
    SET NOCOUNT ON;

    MERGE dbo.monthly_measurements AS t
    USING (
        SELECT
            m.meter_id,
            DATEFROMPARTS(YEAR(m.measured_at), MONTH(m.measured_at), 1) AS measured_month,
            AVG(m.average_current) AS avg_current,
            MAX(lv.row_max_line_voltage) AS max_line_voltage,
            MIN(lv.row_min_line_voltage) AS min_line_voltage,
            MAX(pv.row_max_phase_voltage) AS max_phase_voltage,
            MIN(pv.row_min_phase_voltage) AS min_phase_voltage,
            MAX(m.energy_consumed_total) - MIN(m.energy_consumed_total) AS energy_consumed_kwh,
            AVG(lv.row_avg_line_voltage) AS line_voltage_avg,
            AVG(pv.row_avg_phase_voltage) AS phase_voltage_avg,
            AVG(m.power_factor) AS power_factor,
            MAX(m.max_power) AS max_power,
            MAX(m.reactive_energy_total) - MIN(m.reactive_energy_total) AS reactive_energy_kvarh
        FROM dbo.measurements m
        OUTER APPLY (
            SELECT AVG(v) AS row_avg_line_voltage, MAX(v) AS row_max_line_voltage, MIN(v) AS row_min_line_voltage
            FROM (VALUES
                (CASE WHEN m.voltage_ab IS NULL OR ABS(m.voltage_ab) < 0.001 THEN NULL ELSE m.voltage_ab END),
                (CASE WHEN m.voltage_bc IS NULL OR ABS(m.voltage_bc) < 0.001 THEN NULL ELSE m.voltage_bc END),
                (CASE WHEN m.voltage_ca IS NULL OR ABS(m.voltage_ca) < 0.001 THEN NULL ELSE m.voltage_ca END)
            ) AS src(v)
        ) lv
        OUTER APPLY (
            SELECT AVG(v) AS row_avg_phase_voltage, MAX(v) AS row_max_phase_voltage, MIN(v) AS row_min_phase_voltage
            FROM (VALUES
                (CASE WHEN m.voltage_an IS NULL OR ABS(m.voltage_an) < 0.001 THEN NULL ELSE m.voltage_an END),
                (CASE WHEN m.voltage_bn IS NULL OR ABS(m.voltage_bn) < 0.001 THEN NULL ELSE m.voltage_bn END),
                (CASE WHEN m.voltage_cn IS NULL OR ABS(m.voltage_cn) < 0.001 THEN NULL ELSE m.voltage_cn END)
            ) AS src(v)
        ) pv
        WHERE m.measured_at >= DATEADD(MONTH, -1, GETDATE())
        GROUP BY m.meter_id, YEAR(m.measured_at), MONTH(m.measured_at)
    ) AS s
    ON (t.meter_id = s.meter_id AND t.measured_month = s.measured_month)
    WHEN MATCHED THEN
        UPDATE SET
            avg_current = s.avg_current,
            max_line_voltage = s.max_line_voltage,
            min_line_voltage = s.min_line_voltage,
            max_phase_voltage = s.max_phase_voltage,
            min_phase_voltage = s.min_phase_voltage,
            energy_consumed_kwh = s.energy_consumed_kwh,
            line_voltage_avg = s.line_voltage_avg,
            phase_voltage_avg = s.phase_voltage_avg,
            power_factor = s.power_factor,
            max_power = s.max_power,
            reactive_energy_kvarh = s.reactive_energy_kvarh
    WHEN NOT MATCHED THEN
        INSERT (
            meter_id, measured_month, avg_current,
            max_line_voltage, min_line_voltage, max_phase_voltage, min_phase_voltage,
            energy_consumed_kwh, line_voltage_avg, phase_voltage_avg, power_factor, max_power, reactive_energy_kvarh
        )
        VALUES (
            s.meter_id, s.measured_month, s.avg_current,
            s.max_line_voltage, s.min_line_voltage, s.max_phase_voltage, s.min_phase_voltage,
            s.energy_consumed_kwh, s.line_voltage_avg, s.phase_voltage_avg, s.power_factor, s.max_power, s.reactive_energy_kvarh
        );
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_aggregate_yearly_measurements
AS
BEGIN
    SET NOCOUNT ON;

    MERGE dbo.yearly_measurements AS t
    USING (
        SELECT
            m.meter_id,
            YEAR(m.measured_at) AS measured_year,
            AVG(m.average_current) AS avg_current,
            MAX(lv.row_max_line_voltage) AS max_line_voltage,
            MIN(lv.row_min_line_voltage) AS min_line_voltage,
            MAX(pv.row_max_phase_voltage) AS max_phase_voltage,
            MIN(pv.row_min_phase_voltage) AS min_phase_voltage,
            MAX(m.energy_consumed_total) - MIN(m.energy_consumed_total) AS energy_consumed_kwh,
            AVG(lv.row_avg_line_voltage) AS line_voltage_avg,
            AVG(pv.row_avg_phase_voltage) AS phase_voltage_avg,
            AVG(m.power_factor) AS power_factor,
            MAX(m.max_power) AS max_power,
            MAX(m.reactive_energy_total) - MIN(m.reactive_energy_total) AS reactive_energy_kvarh
        FROM dbo.measurements m
        OUTER APPLY (
            SELECT AVG(v) AS row_avg_line_voltage, MAX(v) AS row_max_line_voltage, MIN(v) AS row_min_line_voltage
            FROM (VALUES
                (CASE WHEN m.voltage_ab IS NULL OR ABS(m.voltage_ab) < 0.001 THEN NULL ELSE m.voltage_ab END),
                (CASE WHEN m.voltage_bc IS NULL OR ABS(m.voltage_bc) < 0.001 THEN NULL ELSE m.voltage_bc END),
                (CASE WHEN m.voltage_ca IS NULL OR ABS(m.voltage_ca) < 0.001 THEN NULL ELSE m.voltage_ca END)
            ) AS src(v)
        ) lv
        OUTER APPLY (
            SELECT AVG(v) AS row_avg_phase_voltage, MAX(v) AS row_max_phase_voltage, MIN(v) AS row_min_phase_voltage
            FROM (VALUES
                (CASE WHEN m.voltage_an IS NULL OR ABS(m.voltage_an) < 0.001 THEN NULL ELSE m.voltage_an END),
                (CASE WHEN m.voltage_bn IS NULL OR ABS(m.voltage_bn) < 0.001 THEN NULL ELSE m.voltage_bn END),
                (CASE WHEN m.voltage_cn IS NULL OR ABS(m.voltage_cn) < 0.001 THEN NULL ELSE m.voltage_cn END)
            ) AS src(v)
        ) pv
        WHERE m.measured_at >= DATEADD(YEAR, -1, GETDATE())
        GROUP BY m.meter_id, YEAR(m.measured_at)
    ) AS s
    ON (t.meter_id = s.meter_id AND t.measured_year = s.measured_year)
    WHEN MATCHED THEN
        UPDATE SET
            avg_current = s.avg_current,
            max_line_voltage = s.max_line_voltage,
            min_line_voltage = s.min_line_voltage,
            max_phase_voltage = s.max_phase_voltage,
            min_phase_voltage = s.min_phase_voltage,
            energy_consumed_kwh = s.energy_consumed_kwh,
            line_voltage_avg = s.line_voltage_avg,
            phase_voltage_avg = s.phase_voltage_avg,
            power_factor = s.power_factor,
            max_power = s.max_power,
            reactive_energy_kvarh = s.reactive_energy_kvarh
    WHEN NOT MATCHED THEN
        INSERT (
            meter_id, measured_year, avg_current,
            max_line_voltage, min_line_voltage, max_phase_voltage, min_phase_voltage,
            energy_consumed_kwh, line_voltage_avg, phase_voltage_avg, power_factor, max_power, reactive_energy_kvarh
        )
        VALUES (
            s.meter_id, s.measured_year, s.avg_current,
            s.max_line_voltage, s.min_line_voltage, s.max_phase_voltage, s.min_phase_voltage,
            s.energy_consumed_kwh, s.line_voltage_avg, s.phase_voltage_avg, s.power_factor, s.max_power, s.reactive_energy_kvarh
        );
END;
GO
