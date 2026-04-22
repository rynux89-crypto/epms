SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/* ---------------------------------------------------------------------------
   Aggregate measurements schema sync with dbo.measurements

   Purpose
   - Keep daily/monthly/yearly aggregate tables aligned with newer columns added
     to dbo.measurements.
   - Preserve existing columns for backward compatibility.
--------------------------------------------------------------------------- */

IF COL_LENGTH('dbo.daily_measurements', 'avg_voltage') IS NOT NULL
    ALTER TABLE dbo.daily_measurements DROP COLUMN avg_voltage;
IF COL_LENGTH('dbo.daily_measurements', 'avg_power_factor') IS NOT NULL
    ALTER TABLE dbo.daily_measurements DROP COLUMN avg_power_factor;
IF COL_LENGTH('dbo.daily_measurements', 'energy_generated_kwh') IS NOT NULL
    ALTER TABLE dbo.daily_measurements DROP COLUMN energy_generated_kwh;
IF COL_LENGTH('dbo.daily_measurements', 'apparent_energy_kvah') IS NOT NULL
    ALTER TABLE dbo.daily_measurements DROP COLUMN apparent_energy_kvah;
IF COL_LENGTH('dbo.daily_measurements', 'max_voltage') IS NOT NULL
    ALTER TABLE dbo.daily_measurements DROP COLUMN max_voltage;
IF COL_LENGTH('dbo.daily_measurements', 'min_voltage') IS NOT NULL
    ALTER TABLE dbo.daily_measurements DROP COLUMN min_voltage;
IF COL_LENGTH('dbo.daily_measurements', 'voltage_unbalance_rate') IS NOT NULL
    ALTER TABLE dbo.daily_measurements DROP COLUMN voltage_unbalance_rate;
IF COL_LENGTH('dbo.daily_measurements', 'harmonic_distortion_rate') IS NOT NULL
    ALTER TABLE dbo.daily_measurements DROP COLUMN harmonic_distortion_rate;
IF COL_LENGTH('dbo.daily_measurements', 'current_variation_rate') IS NOT NULL
    ALTER TABLE dbo.daily_measurements DROP COLUMN current_variation_rate;
IF COL_LENGTH('dbo.monthly_measurements', 'avg_voltage') IS NOT NULL
    ALTER TABLE dbo.monthly_measurements DROP COLUMN avg_voltage;
IF COL_LENGTH('dbo.monthly_measurements', 'avg_power_factor') IS NOT NULL
    ALTER TABLE dbo.monthly_measurements DROP COLUMN avg_power_factor;
IF COL_LENGTH('dbo.monthly_measurements', 'energy_generated_kwh') IS NOT NULL
    ALTER TABLE dbo.monthly_measurements DROP COLUMN energy_generated_kwh;
IF COL_LENGTH('dbo.monthly_measurements', 'apparent_energy_kvah') IS NOT NULL
    ALTER TABLE dbo.monthly_measurements DROP COLUMN apparent_energy_kvah;
IF COL_LENGTH('dbo.monthly_measurements', 'max_voltage') IS NOT NULL
    ALTER TABLE dbo.monthly_measurements DROP COLUMN max_voltage;
IF COL_LENGTH('dbo.monthly_measurements', 'min_voltage') IS NOT NULL
    ALTER TABLE dbo.monthly_measurements DROP COLUMN min_voltage;
IF COL_LENGTH('dbo.monthly_measurements', 'voltage_unbalance_rate') IS NOT NULL
    ALTER TABLE dbo.monthly_measurements DROP COLUMN voltage_unbalance_rate;
IF COL_LENGTH('dbo.monthly_measurements', 'harmonic_distortion_rate') IS NOT NULL
    ALTER TABLE dbo.monthly_measurements DROP COLUMN harmonic_distortion_rate;
IF COL_LENGTH('dbo.monthly_measurements', 'current_variation_rate') IS NOT NULL
    ALTER TABLE dbo.monthly_measurements DROP COLUMN current_variation_rate;
IF COL_LENGTH('dbo.yearly_measurements', 'avg_voltage') IS NOT NULL
    ALTER TABLE dbo.yearly_measurements DROP COLUMN avg_voltage;
IF COL_LENGTH('dbo.yearly_measurements', 'avg_power_factor') IS NOT NULL
    ALTER TABLE dbo.yearly_measurements DROP COLUMN avg_power_factor;
IF COL_LENGTH('dbo.yearly_measurements', 'energy_generated_kwh') IS NOT NULL
    ALTER TABLE dbo.yearly_measurements DROP COLUMN energy_generated_kwh;
IF COL_LENGTH('dbo.yearly_measurements', 'apparent_energy_kvah') IS NOT NULL
    ALTER TABLE dbo.yearly_measurements DROP COLUMN apparent_energy_kvah;
IF COL_LENGTH('dbo.yearly_measurements', 'max_voltage') IS NOT NULL
    ALTER TABLE dbo.yearly_measurements DROP COLUMN max_voltage;
IF COL_LENGTH('dbo.yearly_measurements', 'min_voltage') IS NOT NULL
    ALTER TABLE dbo.yearly_measurements DROP COLUMN min_voltage;
IF COL_LENGTH('dbo.yearly_measurements', 'voltage_unbalance_rate') IS NOT NULL
    ALTER TABLE dbo.yearly_measurements DROP COLUMN voltage_unbalance_rate;
IF COL_LENGTH('dbo.yearly_measurements', 'harmonic_distortion_rate') IS NOT NULL
    ALTER TABLE dbo.yearly_measurements DROP COLUMN harmonic_distortion_rate;
IF COL_LENGTH('dbo.yearly_measurements', 'current_variation_rate') IS NOT NULL
    ALTER TABLE dbo.yearly_measurements DROP COLUMN current_variation_rate;
IF COL_LENGTH('dbo.hourly_measurements', 'avg_voltage') IS NOT NULL
    ALTER TABLE dbo.hourly_measurements DROP COLUMN avg_voltage;
IF COL_LENGTH('dbo.hourly_measurements', 'avg_power_factor') IS NOT NULL
    ALTER TABLE dbo.hourly_measurements DROP COLUMN avg_power_factor;
IF COL_LENGTH('dbo.hourly_measurements', 'energy_generated_kwh') IS NOT NULL
    ALTER TABLE dbo.hourly_measurements DROP COLUMN energy_generated_kwh;
IF COL_LENGTH('dbo.hourly_measurements', 'apparent_energy_kvah') IS NOT NULL
    ALTER TABLE dbo.hourly_measurements DROP COLUMN apparent_energy_kvah;
IF COL_LENGTH('dbo.hourly_measurements', 'max_voltage') IS NOT NULL
    ALTER TABLE dbo.hourly_measurements DROP COLUMN max_voltage;
IF COL_LENGTH('dbo.hourly_measurements', 'min_voltage') IS NOT NULL
    ALTER TABLE dbo.hourly_measurements DROP COLUMN min_voltage;
IF COL_LENGTH('dbo.hourly_measurements', 'voltage_unbalance_rate') IS NOT NULL
    ALTER TABLE dbo.hourly_measurements DROP COLUMN voltage_unbalance_rate;
IF COL_LENGTH('dbo.hourly_measurements', 'harmonic_distortion_rate') IS NOT NULL
    ALTER TABLE dbo.hourly_measurements DROP COLUMN harmonic_distortion_rate;
IF COL_LENGTH('dbo.hourly_measurements', 'current_variation_rate') IS NOT NULL
    ALTER TABLE dbo.hourly_measurements DROP COLUMN current_variation_rate;
GO

IF COL_LENGTH('dbo.daily_measurements', 'line_voltage_avg') IS NULL
    ALTER TABLE dbo.daily_measurements ADD line_voltage_avg FLOAT NULL;
IF COL_LENGTH('dbo.daily_measurements', 'phase_voltage_avg') IS NULL
    ALTER TABLE dbo.daily_measurements ADD phase_voltage_avg FLOAT NULL;
IF COL_LENGTH('dbo.daily_measurements', 'max_line_voltage') IS NULL
    ALTER TABLE dbo.daily_measurements ADD max_line_voltage FLOAT NULL;
IF COL_LENGTH('dbo.daily_measurements', 'min_line_voltage') IS NULL
    ALTER TABLE dbo.daily_measurements ADD min_line_voltage FLOAT NULL;
IF COL_LENGTH('dbo.daily_measurements', 'max_phase_voltage') IS NULL
    ALTER TABLE dbo.daily_measurements ADD max_phase_voltage FLOAT NULL;
IF COL_LENGTH('dbo.daily_measurements', 'min_phase_voltage') IS NULL
    ALTER TABLE dbo.daily_measurements ADD min_phase_voltage FLOAT NULL;
IF COL_LENGTH('dbo.daily_measurements', 'power_factor') IS NULL
    ALTER TABLE dbo.daily_measurements ADD power_factor FLOAT NULL;
IF COL_LENGTH('dbo.daily_measurements', 'max_power') IS NULL
    ALTER TABLE dbo.daily_measurements ADD max_power FLOAT NULL;
IF COL_LENGTH('dbo.daily_measurements', 'reactive_energy_kvarh') IS NULL
    ALTER TABLE dbo.daily_measurements ADD reactive_energy_kvarh FLOAT NULL;
IF COL_LENGTH('dbo.monthly_measurements', 'line_voltage_avg') IS NULL
    ALTER TABLE dbo.monthly_measurements ADD line_voltage_avg FLOAT NULL;
IF COL_LENGTH('dbo.monthly_measurements', 'phase_voltage_avg') IS NULL
    ALTER TABLE dbo.monthly_measurements ADD phase_voltage_avg FLOAT NULL;
IF COL_LENGTH('dbo.monthly_measurements', 'max_line_voltage') IS NULL
    ALTER TABLE dbo.monthly_measurements ADD max_line_voltage FLOAT NULL;
IF COL_LENGTH('dbo.monthly_measurements', 'min_line_voltage') IS NULL
    ALTER TABLE dbo.monthly_measurements ADD min_line_voltage FLOAT NULL;
IF COL_LENGTH('dbo.monthly_measurements', 'max_phase_voltage') IS NULL
    ALTER TABLE dbo.monthly_measurements ADD max_phase_voltage FLOAT NULL;
IF COL_LENGTH('dbo.monthly_measurements', 'min_phase_voltage') IS NULL
    ALTER TABLE dbo.monthly_measurements ADD min_phase_voltage FLOAT NULL;
IF COL_LENGTH('dbo.monthly_measurements', 'power_factor') IS NULL
    ALTER TABLE dbo.monthly_measurements ADD power_factor FLOAT NULL;
IF COL_LENGTH('dbo.monthly_measurements', 'max_power') IS NULL
    ALTER TABLE dbo.monthly_measurements ADD max_power FLOAT NULL;
IF COL_LENGTH('dbo.monthly_measurements', 'reactive_energy_kvarh') IS NULL
    ALTER TABLE dbo.monthly_measurements ADD reactive_energy_kvarh FLOAT NULL;
IF COL_LENGTH('dbo.yearly_measurements', 'line_voltage_avg') IS NULL
    ALTER TABLE dbo.yearly_measurements ADD line_voltage_avg FLOAT NULL;
IF COL_LENGTH('dbo.yearly_measurements', 'phase_voltage_avg') IS NULL
    ALTER TABLE dbo.yearly_measurements ADD phase_voltage_avg FLOAT NULL;
IF COL_LENGTH('dbo.yearly_measurements', 'max_line_voltage') IS NULL
    ALTER TABLE dbo.yearly_measurements ADD max_line_voltage FLOAT NULL;
IF COL_LENGTH('dbo.yearly_measurements', 'min_line_voltage') IS NULL
    ALTER TABLE dbo.yearly_measurements ADD min_line_voltage FLOAT NULL;
IF COL_LENGTH('dbo.yearly_measurements', 'max_phase_voltage') IS NULL
    ALTER TABLE dbo.yearly_measurements ADD max_phase_voltage FLOAT NULL;
IF COL_LENGTH('dbo.yearly_measurements', 'min_phase_voltage') IS NULL
    ALTER TABLE dbo.yearly_measurements ADD min_phase_voltage FLOAT NULL;
IF COL_LENGTH('dbo.yearly_measurements', 'power_factor') IS NULL
    ALTER TABLE dbo.yearly_measurements ADD power_factor FLOAT NULL;
IF COL_LENGTH('dbo.yearly_measurements', 'max_power') IS NULL
    ALTER TABLE dbo.yearly_measurements ADD max_power FLOAT NULL;
IF COL_LENGTH('dbo.yearly_measurements', 'reactive_energy_kvarh') IS NULL
    ALTER TABLE dbo.yearly_measurements ADD reactive_energy_kvarh FLOAT NULL;
IF COL_LENGTH('dbo.hourly_measurements', 'line_voltage_avg') IS NULL
    ALTER TABLE dbo.hourly_measurements ADD line_voltage_avg FLOAT NULL;
IF COL_LENGTH('dbo.hourly_measurements', 'phase_voltage_avg') IS NULL
    ALTER TABLE dbo.hourly_measurements ADD phase_voltage_avg FLOAT NULL;
IF COL_LENGTH('dbo.hourly_measurements', 'max_line_voltage') IS NULL
    ALTER TABLE dbo.hourly_measurements ADD max_line_voltage FLOAT NULL;
IF COL_LENGTH('dbo.hourly_measurements', 'min_line_voltage') IS NULL
    ALTER TABLE dbo.hourly_measurements ADD min_line_voltage FLOAT NULL;
IF COL_LENGTH('dbo.hourly_measurements', 'max_phase_voltage') IS NULL
    ALTER TABLE dbo.hourly_measurements ADD max_phase_voltage FLOAT NULL;
IF COL_LENGTH('dbo.hourly_measurements', 'min_phase_voltage') IS NULL
    ALTER TABLE dbo.hourly_measurements ADD min_phase_voltage FLOAT NULL;
IF COL_LENGTH('dbo.hourly_measurements', 'power_factor') IS NULL
    ALTER TABLE dbo.hourly_measurements ADD power_factor FLOAT NULL;
IF COL_LENGTH('dbo.hourly_measurements', 'max_power') IS NULL
    ALTER TABLE dbo.hourly_measurements ADD max_power FLOAT NULL;
IF COL_LENGTH('dbo.hourly_measurements', 'reactive_energy_kvarh') IS NULL
    ALTER TABLE dbo.hourly_measurements ADD reactive_energy_kvarh FLOAT NULL;
GO

IF OBJECT_ID('dbo.hourly_measurements', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.hourly_measurements (
        hour_id BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        meter_id INT NULL,
        measured_hour DATETIME NOT NULL,
        avg_current FLOAT NULL,
        max_line_voltage FLOAT NULL,
        min_line_voltage FLOAT NULL,
        max_phase_voltage FLOAT NULL,
        min_phase_voltage FLOAT NULL,
        max_current FLOAT NULL,
        min_current FLOAT NULL,
        energy_consumed_kwh FLOAT NULL,
        line_voltage_avg FLOAT NULL,
        phase_voltage_avg FLOAT NULL,
        power_factor FLOAT NULL,
        max_power FLOAT NULL,
        reactive_energy_kvarh FLOAT NULL
    );
END;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.hourly_measurements') AND name = 'idx_hourly_meter_hour')
    CREATE UNIQUE NONCLUSTERED INDEX idx_hourly_meter_hour ON dbo.hourly_measurements (meter_id, measured_hour);
GO

IF NOT EXISTS (
    SELECT 1
    FROM sys.foreign_keys
    WHERE name = 'FK_hourly_measurements_meter'
      AND parent_object_id = OBJECT_ID('dbo.hourly_measurements')
)
BEGIN
    ALTER TABLE dbo.hourly_measurements WITH CHECK
        ADD CONSTRAINT FK_hourly_measurements_meter FOREIGN KEY (meter_id)
        REFERENCES dbo.meters(meter_id);
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
            AVG(m.line_voltage_avg) AS line_voltage_avg,
            AVG(m.phase_voltage_avg) AS phase_voltage_avg,
            AVG(m.power_factor) AS power_factor,
            MAX(m.max_power) AS max_power,
            MAX(m.reactive_energy_total) - MIN(m.reactive_energy_total) AS reactive_energy_kvarh
        FROM dbo.measurements m
        OUTER APPLY (
            SELECT
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
                MAX(v) AS row_max_phase_voltage,
                MIN(v) AS row_min_phase_voltage
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
            meter_id, measured_date,
            avg_current,
            max_line_voltage, min_line_voltage, max_phase_voltage, min_phase_voltage,
            max_current, min_current,
            energy_consumed_kwh,
            line_voltage_avg, phase_voltage_avg, power_factor, max_power,
            reactive_energy_kvarh
        )
        VALUES (
            s.meter_id, s.measured_date,
            s.avg_current,
            s.max_line_voltage, s.min_line_voltage, s.max_phase_voltage, s.min_phase_voltage,
            s.max_current, s.min_current,
            s.energy_consumed_kwh,
            s.line_voltage_avg, s.phase_voltage_avg, s.power_factor, s.max_power,
            s.reactive_energy_kvarh
        );
END;
GO

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
            AVG(m.line_voltage_avg) AS line_voltage_avg,
            AVG(m.phase_voltage_avg) AS phase_voltage_avg,
            AVG(m.power_factor) AS power_factor,
            MAX(m.max_power) AS max_power,
            MAX(m.reactive_energy_total) - MIN(m.reactive_energy_total) AS reactive_energy_kvarh
        FROM dbo.measurements m
        OUTER APPLY (
            SELECT
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
            meter_id, measured_hour,
            avg_current,
            max_line_voltage, min_line_voltage, max_phase_voltage, min_phase_voltage,
            max_current, min_current,
            energy_consumed_kwh,
            line_voltage_avg, phase_voltage_avg, power_factor, max_power,
            reactive_energy_kvarh
        )
        VALUES (
            s.meter_id, s.measured_hour,
            s.avg_current,
            s.max_line_voltage, s.min_line_voltage, s.max_phase_voltage, s.min_phase_voltage,
            s.max_current, s.min_current,
            s.energy_consumed_kwh,
            s.line_voltage_avg, s.phase_voltage_avg, s.power_factor, s.max_power,
            s.reactive_energy_kvarh
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
            AVG(m.line_voltage_avg) AS line_voltage_avg,
            AVG(m.phase_voltage_avg) AS phase_voltage_avg,
            AVG(m.power_factor) AS power_factor,
            MAX(m.max_power) AS max_power,
            MAX(m.reactive_energy_total) - MIN(m.reactive_energy_total) AS reactive_energy_kvarh
        FROM dbo.measurements m
        OUTER APPLY (
            SELECT
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
                MAX(v) AS row_max_phase_voltage,
                MIN(v) AS row_min_phase_voltage
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
            meter_id, measured_month,
            avg_current,
            max_line_voltage, min_line_voltage, max_phase_voltage, min_phase_voltage,
            energy_consumed_kwh,
            line_voltage_avg, phase_voltage_avg, power_factor, max_power,
            reactive_energy_kvarh
        )
        VALUES (
            s.meter_id, s.measured_month,
            s.avg_current,
            s.max_line_voltage, s.min_line_voltage, s.max_phase_voltage, s.min_phase_voltage,
            s.energy_consumed_kwh,
            s.line_voltage_avg, s.phase_voltage_avg, s.power_factor, s.max_power,
            s.reactive_energy_kvarh
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
            AVG(m.line_voltage_avg) AS line_voltage_avg,
            AVG(m.phase_voltage_avg) AS phase_voltage_avg,
            AVG(m.power_factor) AS power_factor,
            MAX(m.max_power) AS max_power,
            MAX(m.reactive_energy_total) - MIN(m.reactive_energy_total) AS reactive_energy_kvarh
        FROM dbo.measurements m
        OUTER APPLY (
            SELECT
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
                MAX(v) AS row_max_phase_voltage,
                MIN(v) AS row_min_phase_voltage
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
            meter_id, measured_year,
            avg_current,
            max_line_voltage, min_line_voltage, max_phase_voltage, min_phase_voltage,
            energy_consumed_kwh,
            line_voltage_avg, phase_voltage_avg, power_factor, max_power,
            reactive_energy_kvarh
        )
        VALUES (
            s.meter_id, s.measured_year,
            s.avg_current,
            s.max_line_voltage, s.min_line_voltage, s.max_phase_voltage, s.min_phase_voltage,
            s.energy_consumed_kwh,
            s.line_voltage_avg, s.phase_voltage_avg, s.power_factor, s.max_power,
            s.reactive_energy_kvarh
        );
END;
GO

CREATE OR ALTER VIEW dbo.vw_daily_measurements
AS
SELECT
    m.meter_id,
    m.name AS meter_name,
    m.panel_name,
    m.building_name,
    m.usage_type,
    d.day_id,
    d.measured_date,
    d.avg_current,
    d.max_line_voltage,
    d.min_line_voltage,
    d.max_phase_voltage,
    d.min_phase_voltage,
    d.max_current,
    d.min_current,
    d.energy_consumed_kwh,
    d.reactive_energy_kvarh,
    d.line_voltage_avg,
    d.phase_voltage_avg,
    d.power_factor,
    d.max_power
FROM dbo.daily_measurements d
INNER JOIN dbo.meters m ON m.meter_id = d.meter_id;
GO

CREATE OR ALTER VIEW dbo.vw_hourly_measurements
AS
SELECT
    m.meter_id,
    m.name AS meter_name,
    m.panel_name,
    m.building_name,
    m.usage_type,
    h.hour_id,
    h.measured_hour,
    h.avg_current,
    h.max_line_voltage,
    h.min_line_voltage,
    h.max_phase_voltage,
    h.min_phase_voltage,
    h.max_current,
    h.min_current,
    h.energy_consumed_kwh,
    h.reactive_energy_kvarh,
    h.line_voltage_avg,
    h.phase_voltage_avg,
    h.power_factor,
    h.max_power
FROM dbo.hourly_measurements h
INNER JOIN dbo.meters m ON m.meter_id = h.meter_id;
GO

CREATE OR ALTER VIEW dbo.vw_monthly_measurements
AS
SELECT
    m.meter_id,
    m.name AS meter_name,
    m.panel_name,
    m.building_name,
    m.usage_type,
    mm.month_id,
    mm.measured_month,
    mm.avg_current,
    mm.max_line_voltage,
    mm.min_line_voltage,
    mm.max_phase_voltage,
    mm.min_phase_voltage,
    mm.energy_consumed_kwh,
    mm.reactive_energy_kvarh,
    mm.line_voltage_avg,
    mm.phase_voltage_avg,
    mm.power_factor,
    mm.max_power
FROM dbo.monthly_measurements mm
INNER JOIN dbo.meters m ON m.meter_id = mm.meter_id;
GO

CREATE OR ALTER VIEW dbo.vw_yearly_measurements
AS
SELECT
    m.meter_id,
    m.name AS meter_name,
    m.panel_name,
    m.building_name,
    m.usage_type,
    y.year_id,
    y.measured_year,
    y.avg_current,
    y.max_line_voltage,
    y.min_line_voltage,
    y.max_phase_voltage,
    y.min_phase_voltage,
    y.energy_consumed_kwh,
    y.reactive_energy_kvarh,
    y.line_voltage_avg,
    y.phase_voltage_avg,
    y.power_factor,
    y.max_power
FROM dbo.yearly_measurements y
INNER JOIN dbo.meters m ON m.meter_id = y.meter_id;
GO
