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
        voltage_max = vm.voltage_max_calc,
        voltage_min = vm.voltage_min_calc,
        current_max = cm.current_max_calc,
        current_min = cm.current_min_calc,
        power_factor_min = pf.power_factor_min_calc,
        max_power = pw.max_power_calc
    FROM dbo.measurements m
    INNER JOIN inserted i ON i.measurement_id = m.measurement_id
    OUTER APPLY (
        SELECT MAX(v) AS voltage_max_calc, MIN(v) AS voltage_min_calc
        FROM (VALUES
            (m.voltage_ab),(m.voltage_bc),(m.voltage_ca),
            (m.voltage_an),(m.voltage_bn),(m.voltage_cn),
            (m.voltage_phase_a),(m.voltage_phase_b),(m.voltage_phase_c),
            (m.average_voltage),(m.line_voltage_avg),(m.phase_voltage_avg)
        ) AS src(v)
        WHERE v IS NOT NULL
    ) vm
    OUTER APPLY (
        SELECT MAX(v) AS current_max_calc, MIN(v) AS current_min_calc
        FROM (VALUES
            (m.current_a),(m.current_b),(m.current_c),(m.current_n)
        ) AS src(v)
        WHERE v IS NOT NULL
    ) cm
    OUTER APPLY (
        SELECT MIN(v) AS power_factor_min_calc
        FROM (VALUES
            (m.power_factor_a),(m.power_factor_b),(m.power_factor_c),
            (m.power_factor),(m.power_factor_avg)
        ) AS src(v)
        WHERE v IS NOT NULL
    ) pf
    OUTER APPLY (
        SELECT MAX(v) AS max_power_calc
        FROM (VALUES
            (CASE WHEN m.active_power_total IS NULL THEN NULL ELSE ABS(m.active_power_total) END),
            (CASE WHEN m.active_power_a IS NULL THEN NULL ELSE ABS(m.active_power_a) END),
            (CASE WHEN m.active_power_b IS NULL THEN NULL ELSE ABS(m.active_power_b) END),
            (CASE WHEN m.active_power_c IS NULL THEN NULL ELSE ABS(m.active_power_c) END)
        ) AS src(v)
        WHERE v IS NOT NULL
    ) pw;
END;
GO
