SET NOCOUNT ON;

SELECT
    m.meter_id,
    DATEADD(HOUR, DATEDIFF(HOUR, 0, m.measured_at), 0) AS measured_hour,
    AVG(lv.row_avg_line_voltage) AS line_voltage_avg,
    AVG(pv.row_avg_phase_voltage) AS phase_voltage_avg,
    MAX(lv.row_max_line_voltage) AS max_line_voltage,
    MIN(lv.row_min_line_voltage) AS min_line_voltage,
    MAX(pv.row_max_phase_voltage) AS max_phase_voltage,
    MIN(pv.row_min_phase_voltage) AS min_phase_voltage
INTO #hourly_src
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
GROUP BY m.meter_id, DATEADD(HOUR, DATEDIFF(HOUR, 0, m.measured_at), 0);

SELECT
    m.meter_id,
    CAST(m.measured_at AS DATE) AS measured_date,
    AVG(lv.row_avg_line_voltage) AS line_voltage_avg,
    AVG(pv.row_avg_phase_voltage) AS phase_voltage_avg,
    MAX(lv.row_max_line_voltage) AS max_line_voltage,
    MIN(lv.row_min_line_voltage) AS min_line_voltage,
    MAX(pv.row_max_phase_voltage) AS max_phase_voltage,
    MIN(pv.row_min_phase_voltage) AS min_phase_voltage
INTO #daily_src
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
GROUP BY m.meter_id, CAST(m.measured_at AS DATE);

SELECT
    m.meter_id,
    DATEFROMPARTS(YEAR(m.measured_at), MONTH(m.measured_at), 1) AS measured_month,
    AVG(lv.row_avg_line_voltage) AS line_voltage_avg,
    AVG(pv.row_avg_phase_voltage) AS phase_voltage_avg,
    MAX(lv.row_max_line_voltage) AS max_line_voltage,
    MIN(lv.row_min_line_voltage) AS min_line_voltage,
    MAX(pv.row_max_phase_voltage) AS max_phase_voltage,
    MIN(pv.row_min_phase_voltage) AS min_phase_voltage
INTO #monthly_src
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
GROUP BY m.meter_id, DATEFROMPARTS(YEAR(m.measured_at), MONTH(m.measured_at), 1);

SELECT
    m.meter_id,
    YEAR(m.measured_at) AS measured_year,
    AVG(lv.row_avg_line_voltage) AS line_voltage_avg,
    AVG(pv.row_avg_phase_voltage) AS phase_voltage_avg,
    MAX(lv.row_max_line_voltage) AS max_line_voltage,
    MIN(lv.row_min_line_voltage) AS min_line_voltage,
    MAX(pv.row_max_phase_voltage) AS max_phase_voltage,
    MIN(pv.row_min_phase_voltage) AS min_phase_voltage
INTO #yearly_src
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
GROUP BY m.meter_id, YEAR(m.measured_at);

UPDATE h
SET h.line_voltage_avg = s.line_voltage_avg,
    h.phase_voltage_avg = s.phase_voltage_avg,
    h.max_line_voltage = s.max_line_voltage,
    h.min_line_voltage = s.min_line_voltage,
    h.max_phase_voltage = s.max_phase_voltage,
    h.min_phase_voltage = s.min_phase_voltage
FROM dbo.hourly_measurements h
JOIN #hourly_src s ON s.meter_id = h.meter_id AND s.measured_hour = h.measured_hour;

UPDATE d
SET d.line_voltage_avg = s.line_voltage_avg,
    d.phase_voltage_avg = s.phase_voltage_avg,
    d.max_line_voltage = s.max_line_voltage,
    d.min_line_voltage = s.min_line_voltage,
    d.max_phase_voltage = s.max_phase_voltage,
    d.min_phase_voltage = s.min_phase_voltage
FROM dbo.daily_measurements d
JOIN #daily_src s ON s.meter_id = d.meter_id AND s.measured_date = d.measured_date;

UPDATE m
SET m.line_voltage_avg = s.line_voltage_avg,
    m.phase_voltage_avg = s.phase_voltage_avg,
    m.max_line_voltage = s.max_line_voltage,
    m.min_line_voltage = s.min_line_voltage,
    m.max_phase_voltage = s.max_phase_voltage,
    m.min_phase_voltage = s.min_phase_voltage
FROM dbo.monthly_measurements m
JOIN #monthly_src s ON s.meter_id = m.meter_id AND s.measured_month = m.measured_month;

UPDATE y
SET y.line_voltage_avg = s.line_voltage_avg,
    y.phase_voltage_avg = s.phase_voltage_avg,
    y.max_line_voltage = s.max_line_voltage,
    y.min_line_voltage = s.min_line_voltage,
    y.max_phase_voltage = s.max_phase_voltage,
    y.min_phase_voltage = s.min_phase_voltage
FROM dbo.yearly_measurements y
JOIN #yearly_src s ON s.meter_id = y.meter_id AND s.measured_year = y.measured_year;
