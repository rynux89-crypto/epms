USE epms;
GO

IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE object_id = OBJECT_ID(N'dbo.plc_ai_samples')
      AND name = N'IX_plc_ai_samples_meter_reg_measured_at'
)
BEGIN
    CREATE NONCLUSTERED INDEX IX_plc_ai_samples_meter_reg_measured_at
    ON dbo.plc_ai_samples (meter_id, reg_address, measured_at DESC)
    INCLUDE (value_float);
END
GO

