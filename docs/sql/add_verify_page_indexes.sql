IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID(N'dbo.plc_ai_samples')
      AND name = N'IX_plc_ai_samples_plc_meter_measured_reg'
)
BEGIN
    CREATE NONCLUSTERED INDEX IX_plc_ai_samples_plc_meter_measured_reg
    ON dbo.plc_ai_samples (plc_id, meter_id, measured_at DESC, reg_address)
    INCLUDE (value_float, byte_order, quality);
END;

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID(N'dbo.plc_ai_samples')
      AND name = N'IX_plc_ai_samples_meter_reg_measured_at'
)
BEGIN
    CREATE NONCLUSTERED INDEX IX_plc_ai_samples_meter_reg_measured_at
    ON dbo.plc_ai_samples (meter_id, reg_address, measured_at DESC)
    INCLUDE (value_float);
END;

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID(N'dbo.harmonic_measurements')
      AND name = N'IX_harmonic_measurements_meter_time'
)
BEGIN
    CREATE NONCLUSTERED INDEX IX_harmonic_measurements_meter_time
    ON dbo.harmonic_measurements (meter_id, measured_at DESC);
END;
