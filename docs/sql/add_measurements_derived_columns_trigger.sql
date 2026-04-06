/*
   Auto-maintain derived min/max columns on dbo.measurements.

   Columns maintained
   - line_voltage_avg
   - phase_voltage_avg
   - average_current
   - voltage_max
   - voltage_min
   - current_max
   - current_min
   - power_factor_min
   - max_power
*/

USE EPMS;
GO

CREATE OR ALTER TRIGGER dbo.trg_measurements_derive_minmax
ON dbo.measurements
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE m
    SET
        line_voltage_avg = CASE
            WHEN i.line_voltage_avg IS NOT NULL AND ABS(i.line_voltage_avg) >= 0.001 THEN i.line_voltage_avg
            ELSE vv.line_voltage_avg_calc
        END,
        phase_voltage_avg = CASE
            WHEN i.phase_voltage_avg IS NOT NULL AND ABS(i.phase_voltage_avg) >= 0.001 THEN i.phase_voltage_avg
            ELSE vv.phase_voltage_avg_calc
        END,
        average_current = CASE
            WHEN i.average_current IS NOT NULL AND ABS(i.average_current) >= 0.001 THEN i.average_current
            ELSE cm.current_avg_calc
        END,
        voltage_max = vm.voltage_max_calc,
        voltage_min = vm.voltage_min_calc,
        current_max = cm.current_max_calc,
        current_min = cm.current_min_calc,
        power_factor_min = pf.power_factor_min_calc,
        max_power = CASE
            WHEN ps.peak_value IS NOT NULL THEN ps.peak_value
            WHEN i.max_power IS NOT NULL AND ABS(i.max_power) >= 0.001 THEN i.max_power
            ELSE pw.max_power_calc
        END
    FROM dbo.measurements m
    INNER JOIN inserted i
        ON i.measurement_id = m.measurement_id
    OUTER APPLY (
        SELECT
            AVG(line_v) AS line_voltage_avg_calc,
            AVG(phase_v) AS phase_voltage_avg_calc
        FROM (
            SELECT
                CASE WHEN ABS(COALESCE(m.voltage_ab, 0)) < 0.001 THEN NULL ELSE m.voltage_ab END AS line_v,
                CASE WHEN ABS(COALESCE(m.voltage_an, 0)) < 0.001 THEN NULL ELSE m.voltage_an END AS phase_v
            UNION ALL
            SELECT
                CASE WHEN ABS(COALESCE(m.voltage_bc, 0)) < 0.001 THEN NULL ELSE m.voltage_bc END,
                CASE WHEN ABS(COALESCE(m.voltage_bn, 0)) < 0.001 THEN NULL ELSE m.voltage_bn END
            UNION ALL
            SELECT
                CASE WHEN ABS(COALESCE(m.voltage_ca, 0)) < 0.001 THEN NULL ELSE m.voltage_ca END,
                CASE WHEN ABS(COALESCE(m.voltage_cn, 0)) < 0.001 THEN NULL ELSE m.voltage_cn END
        ) s
    ) vv
    OUTER APPLY (
        SELECT
            MAX(v) AS voltage_max_calc,
            MIN(v) AS voltage_min_calc
        FROM (VALUES
            (CASE WHEN m.voltage_ab IS NULL OR ABS(m.voltage_ab) < 0.001 THEN 0 ELSE m.voltage_ab END),
            (CASE WHEN m.voltage_bc IS NULL OR ABS(m.voltage_bc) < 0.001 THEN 0 ELSE m.voltage_bc END),
            (CASE WHEN m.voltage_ca IS NULL OR ABS(m.voltage_ca) < 0.001 THEN 0 ELSE m.voltage_ca END),
            (CASE WHEN m.voltage_an IS NULL OR ABS(m.voltage_an) < 0.001 THEN 0 ELSE m.voltage_an END),
            (CASE WHEN m.voltage_bn IS NULL OR ABS(m.voltage_bn) < 0.001 THEN 0 ELSE m.voltage_bn END),
            (CASE WHEN m.voltage_cn IS NULL OR ABS(m.voltage_cn) < 0.001 THEN 0 ELSE m.voltage_cn END),
            (CASE WHEN m.average_voltage IS NULL OR ABS(m.average_voltage) < 0.001 THEN 0 ELSE m.average_voltage END),
            (CASE WHEN m.line_voltage_avg IS NULL OR ABS(m.line_voltage_avg) < 0.001 THEN 0 ELSE m.line_voltage_avg END),
            (CASE WHEN m.phase_voltage_avg IS NULL OR ABS(m.phase_voltage_avg) < 0.001 THEN 0 ELSE m.phase_voltage_avg END)
        ) AS src(v)
        WHERE v IS NOT NULL
    ) vm
    OUTER APPLY (
        SELECT
            AVG(v) AS current_avg_calc,
            MAX(v) AS current_max_calc,
            MIN(v) AS current_min_calc
        FROM (VALUES
            (m.current_a),
            (m.current_b),
            (m.current_c),
            (m.current_n)
        ) AS src(v)
        WHERE v IS NOT NULL
    ) cm
    OUTER APPLY (
        SELECT
            MIN(v) AS power_factor_min_calc
        FROM (VALUES
            (m.power_factor_a),
            (m.power_factor_b),
            (m.power_factor_c),
            (m.power_factor),
            (m.power_factor_avg)
        ) AS src(v)
        WHERE v IS NOT NULL
    ) pf
    OUTER APPLY (
        SELECT
            MAX(v) AS max_power_calc
        FROM (VALUES
            (CASE WHEN m.active_power_total IS NULL THEN NULL ELSE ABS(m.active_power_total) END),
            (CASE WHEN m.active_power_a IS NULL THEN NULL ELSE ABS(m.active_power_a) END),
            (CASE WHEN m.active_power_b IS NULL THEN NULL ELSE ABS(m.active_power_b) END),
            (CASE WHEN m.active_power_c IS NULL THEN NULL ELSE ABS(m.active_power_c) END)
        ) AS src(v)
        WHERE v IS NOT NULL
    ) pw
    OUTER APPLY (
        SELECT TOP 1 s.value_float AS peak_value
        FROM dbo.plc_ai_mapping_master am
        INNER JOIN dbo.plc_ai_samples s
            ON s.meter_id = m.meter_id
           AND s.reg_address = am.reg_address
        WHERE am.enabled = 1
          AND am.meter_id = m.meter_id
          AND (am.measurement_column = 'max_power' OR am.token = 'PEAK')
          AND s.measured_at BETWEEN DATEADD(SECOND, -2, m.measured_at) AND DATEADD(SECOND, 2, m.measured_at)
        ORDER BY ABS(DATEDIFF(SECOND, s.measured_at, m.measured_at)), ABS(DATEDIFF(MINUTE, s.measured_at, m.measured_at))
    ) ps;
END;
GO

UPDATE m
SET
    line_voltage_avg = CASE
        WHEN m.line_voltage_avg IS NOT NULL AND ABS(m.line_voltage_avg) >= 0.001 THEN m.line_voltage_avg
        ELSE vv.line_voltage_avg_calc
    END,
    phase_voltage_avg = CASE
        WHEN m.phase_voltage_avg IS NOT NULL AND ABS(m.phase_voltage_avg) >= 0.001 THEN m.phase_voltage_avg
        ELSE vv.phase_voltage_avg_calc
    END,
    average_current = CASE
        WHEN m.average_current IS NOT NULL AND ABS(m.average_current) >= 0.001 THEN m.average_current
        ELSE cm.current_avg_calc
    END,
    voltage_max = vm.voltage_max_calc,
    voltage_min = vm.voltage_min_calc,
    current_max = cm.current_max_calc,
    current_min = cm.current_min_calc,
    power_factor_min = pf.power_factor_min_calc,
    max_power = COALESCE(ps.peak_value, pw.max_power_calc)
FROM dbo.measurements m
OUTER APPLY (
    SELECT
        AVG(line_v) AS line_voltage_avg_calc,
        AVG(phase_v) AS phase_voltage_avg_calc
    FROM (
        SELECT
            CASE WHEN ABS(COALESCE(m.voltage_ab, 0)) < 0.001 THEN NULL ELSE m.voltage_ab END AS line_v,
            CASE WHEN ABS(COALESCE(m.voltage_an, 0)) < 0.001 THEN NULL ELSE m.voltage_an END AS phase_v
        UNION ALL
        SELECT
            CASE WHEN ABS(COALESCE(m.voltage_bc, 0)) < 0.001 THEN NULL ELSE m.voltage_bc END,
            CASE WHEN ABS(COALESCE(m.voltage_bn, 0)) < 0.001 THEN NULL ELSE m.voltage_bn END
        UNION ALL
        SELECT
            CASE WHEN ABS(COALESCE(m.voltage_ca, 0)) < 0.001 THEN NULL ELSE m.voltage_ca END,
            CASE WHEN ABS(COALESCE(m.voltage_cn, 0)) < 0.001 THEN NULL ELSE m.voltage_cn END
    ) s
) vv
OUTER APPLY (
    SELECT
        MAX(v) AS voltage_max_calc,
        MIN(v) AS voltage_min_calc
    FROM (VALUES
        (CASE WHEN m.voltage_ab IS NULL OR ABS(m.voltage_ab) < 0.001 THEN 0 ELSE m.voltage_ab END),
        (CASE WHEN m.voltage_bc IS NULL OR ABS(m.voltage_bc) < 0.001 THEN 0 ELSE m.voltage_bc END),
        (CASE WHEN m.voltage_ca IS NULL OR ABS(m.voltage_ca) < 0.001 THEN 0 ELSE m.voltage_ca END),
        (CASE WHEN m.voltage_an IS NULL OR ABS(m.voltage_an) < 0.001 THEN 0 ELSE m.voltage_an END),
        (CASE WHEN m.voltage_bn IS NULL OR ABS(m.voltage_bn) < 0.001 THEN 0 ELSE m.voltage_bn END),
        (CASE WHEN m.voltage_cn IS NULL OR ABS(m.voltage_cn) < 0.001 THEN 0 ELSE m.voltage_cn END),
        (CASE WHEN m.average_voltage IS NULL OR ABS(m.average_voltage) < 0.001 THEN 0 ELSE m.average_voltage END),
        (CASE WHEN m.line_voltage_avg IS NULL OR ABS(m.line_voltage_avg) < 0.001 THEN 0 ELSE m.line_voltage_avg END),
        (CASE WHEN m.phase_voltage_avg IS NULL OR ABS(m.phase_voltage_avg) < 0.001 THEN 0 ELSE m.phase_voltage_avg END)
    ) AS src(v)
    WHERE v IS NOT NULL
) vm
OUTER APPLY (
    SELECT
        AVG(v) AS current_avg_calc,
        MAX(v) AS current_max_calc,
        MIN(v) AS current_min_calc
    FROM (VALUES
        (m.current_a),
        (m.current_b),
        (m.current_c),
        (m.current_n)
    ) AS src(v)
    WHERE v IS NOT NULL
) cm
OUTER APPLY (
    SELECT
        MIN(v) AS power_factor_min_calc
    FROM (VALUES
        (m.power_factor_a),
        (m.power_factor_b),
        (m.power_factor_c),
        (m.power_factor),
        (m.power_factor_avg)
    ) AS src(v)
    WHERE v IS NOT NULL
) pf
OUTER APPLY (
    SELECT
        MAX(v) AS max_power_calc
    FROM (VALUES
        (CASE WHEN m.active_power_total IS NULL THEN NULL ELSE ABS(m.active_power_total) END),
        (CASE WHEN m.active_power_a IS NULL THEN NULL ELSE ABS(m.active_power_a) END),
        (CASE WHEN m.active_power_b IS NULL THEN NULL ELSE ABS(m.active_power_b) END),
        (CASE WHEN m.active_power_c IS NULL THEN NULL ELSE ABS(m.active_power_c) END)
    ) AS src(v)
    WHERE v IS NOT NULL
) pw
OUTER APPLY (
    SELECT TOP 1 s.value_float AS peak_value
    FROM dbo.plc_ai_mapping_master am
    INNER JOIN dbo.plc_ai_samples s
        ON s.meter_id = m.meter_id
       AND s.reg_address = am.reg_address
    WHERE am.enabled = 1
      AND am.meter_id = m.meter_id
      AND (am.measurement_column = 'max_power' OR am.token = 'PEAK')
      AND s.measured_at BETWEEN DATEADD(SECOND, -2, m.measured_at) AND DATEADD(SECOND, 2, m.measured_at)
    ORDER BY ABS(DATEDIFF(SECOND, s.measured_at, m.measured_at)), ABS(DATEDIFF(MINUTE, s.measured_at, m.measured_at))
) ps
;
GO
