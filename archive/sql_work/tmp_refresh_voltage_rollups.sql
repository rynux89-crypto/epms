SET NOCOUNT ON;
WITH hourly_src AS (
    SELECT meter_id, DATEADD(HOUR, DATEDIFF(HOUR, 0, measured_at), 0) AS measured_hour,
           MAX(voltage_max) AS max_voltage,
           MIN(voltage_min) AS min_voltage
    FROM dbo.measurements
    GROUP BY meter_id, DATEADD(HOUR, DATEDIFF(HOUR, 0, measured_at), 0)
)
UPDATE hm
SET hm.max_voltage = s.max_voltage,
    hm.min_voltage = s.min_voltage
FROM dbo.hourly_measurements hm
JOIN hourly_src s ON s.meter_id = hm.meter_id AND s.measured_hour = hm.measured_hour;
SELECT @@ROWCOUNT AS hourly_updated;

WITH daily_src AS (
    SELECT meter_id, CAST(measured_at AS date) AS measured_date,
           MAX(voltage_max) AS max_voltage,
           MIN(voltage_min) AS min_voltage
    FROM dbo.measurements
    GROUP BY meter_id, CAST(measured_at AS date)
)
UPDATE dm
SET dm.max_voltage = s.max_voltage,
    dm.min_voltage = s.min_voltage
FROM dbo.daily_measurements dm
JOIN daily_src s ON s.meter_id = dm.meter_id AND s.measured_date = dm.measured_date;
SELECT @@ROWCOUNT AS daily_updated;

WITH monthly_src AS (
    SELECT meter_id, DATEFROMPARTS(YEAR(measured_at), MONTH(measured_at), 1) AS measured_month,
           MAX(voltage_max) AS max_voltage,
           MIN(voltage_min) AS min_voltage
    FROM dbo.measurements
    GROUP BY meter_id, DATEFROMPARTS(YEAR(measured_at), MONTH(measured_at), 1)
)
UPDATE mm
SET mm.max_voltage = s.max_voltage,
    mm.min_voltage = s.min_voltage
FROM dbo.monthly_measurements mm
JOIN monthly_src s ON s.meter_id = mm.meter_id AND s.measured_month = mm.measured_month;
SELECT @@ROWCOUNT AS monthly_updated;

WITH yearly_src AS (
    SELECT meter_id, YEAR(measured_at) AS measured_year,
           MAX(voltage_max) AS max_voltage,
           MIN(voltage_min) AS min_voltage
    FROM dbo.measurements
    GROUP BY meter_id, YEAR(measured_at)
)
UPDATE ym
SET ym.max_voltage = s.max_voltage,
    ym.min_voltage = s.min_voltage
FROM dbo.yearly_measurements ym
JOIN yearly_src s ON s.meter_id = ym.meter_id AND s.measured_year = ym.measured_year;
SELECT @@ROWCOUNT AS yearly_updated;
