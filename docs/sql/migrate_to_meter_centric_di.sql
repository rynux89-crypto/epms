SET NOCOUNT ON;
SET XACT_ABORT ON;

-- Follow with docs/sql/seed_di_virtual_meters.sql to create DI-only
-- representative meters for any logical DI groups that still cannot map
-- to an existing physical power meter after this first-pass migration.

BEGIN TRY
    BEGIN TRANSACTION;

    IF COL_LENGTH('dbo.plc_di_mapping_master', 'meter_id') IS NULL
        ALTER TABLE dbo.plc_di_mapping_master ADD meter_id INT NULL;

    EXEC('
        ;WITH meter_seed AS (
            SELECT
                d.plc_id,
                d.point_id,
                d.di_address,
                d.bit_no,
                COALESCE(mp_exact.meter_id, mp_name.meter_id, mp_panel.meter_id) AS meter_id
            FROM dbo.plc_di_mapping_master d
            OUTER APPLY (
                SELECT TOP 1 m.meter_id
                FROM dbo.meters m
                WHERE d.item_name IS NOT NULL
                  AND d.panel_name IS NOT NULL
                  AND UPPER(LTRIM(RTRIM(m.name))) = UPPER(LTRIM(RTRIM(d.item_name)))
                  AND UPPER(LTRIM(RTRIM(m.panel_name))) = UPPER(LTRIM(RTRIM(d.panel_name)))
                ORDER BY m.meter_id
            ) mp_exact
            OUTER APPLY (
                SELECT TOP 1 m.meter_id
                FROM dbo.meters m
                WHERE mp_exact.meter_id IS NULL
                  AND d.item_name IS NOT NULL
                  AND UPPER(LTRIM(RTRIM(m.name))) = UPPER(LTRIM(RTRIM(d.item_name)))
                ORDER BY m.meter_id
            ) mp_name
            OUTER APPLY (
                SELECT CASE WHEN COUNT(*) = 1 THEN MIN(m.meter_id) END AS meter_id
                FROM dbo.meters m
                WHERE mp_exact.meter_id IS NULL
                  AND mp_name.meter_id IS NULL
                  AND d.panel_name IS NOT NULL
                  AND UPPER(LTRIM(RTRIM(m.panel_name))) = UPPER(LTRIM(RTRIM(d.panel_name)))
            ) mp_panel
        )
        UPDATE d
        SET meter_id = s.meter_id
        FROM dbo.plc_di_mapping_master d
        JOIN meter_seed s
          ON s.plc_id = d.plc_id
         AND s.point_id = d.point_id
         AND s.di_address = d.di_address
         AND s.bit_no = d.bit_no
        WHERE d.meter_id IS NULL
          AND s.meter_id IS NOT NULL;
    ');

    IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.plc_di_mapping_master') AND name = 'IX_plc_di_mapping_master_meter')
        CREATE INDEX IX_plc_di_mapping_master_meter ON dbo.plc_di_mapping_master (meter_id, plc_id, point_id, di_address, bit_no);

    IF NOT EXISTS (
        SELECT 1 FROM sys.foreign_keys
        WHERE parent_object_id = OBJECT_ID('dbo.plc_di_mapping_master')
          AND name = 'FK_plc_di_mapping_master_meter'
    )
        ALTER TABLE dbo.plc_di_mapping_master WITH NOCHECK
        ADD CONSTRAINT FK_plc_di_mapping_master_meter FOREIGN KEY (meter_id) REFERENCES dbo.meters(meter_id);

    IF COL_LENGTH('dbo.device_events', 'meter_id') IS NULL
        ALTER TABLE dbo.device_events ADD meter_id INT NULL;

    EXEC('
        UPDATE dbo.device_events
        SET meter_id = device_id
        WHERE meter_id IS NULL
          AND device_id IS NOT NULL;
    ');

    IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.device_events') AND name = 'idx_device_event_meter_time')
        CREATE INDEX idx_device_event_meter_time ON dbo.device_events (meter_id, event_time DESC);

    IF NOT EXISTS (
        SELECT 1 FROM sys.foreign_keys
        WHERE parent_object_id = OBJECT_ID('dbo.device_events')
          AND name = 'FK_device_events_meter_id'
    )
        ALTER TABLE dbo.device_events WITH NOCHECK
        ADD CONSTRAINT FK_device_events_meter_id FOREIGN KEY (meter_id) REFERENCES dbo.meters(meter_id);

    IF OBJECT_ID(N'[dbo].[vw_device_event_log]', N'V') IS NOT NULL
        DROP VIEW [dbo].[vw_device_event_log];

    EXEC('
        CREATE VIEW dbo.vw_device_event_log AS
        SELECT
            COALESCE(e.meter_id, e.device_id) AS meter_id,
            m.name AS meter_name,
            m.panel_name,
            m.building_name,
            m.usage_type,
            e.event_id,
            e.event_type,
            e.event_time,
            e.restored_time,
            e.severity,
            e.description,
            e.trip_count,
            e.outage_count,
            e.switch_count,
            e.downtime_minutes,
            e.duration_seconds,
            e.operating_time_minutes
        FROM dbo.device_events e
        LEFT JOIN dbo.meters m
          ON m.meter_id = COALESCE(e.meter_id, e.device_id);
    ');

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;

EXEC('
    SELECT
        (SELECT COUNT(*) FROM dbo.plc_di_mapping_master WHERE meter_id IS NOT NULL) AS di_mapping_with_meter_id,
        (SELECT COUNT(*) FROM dbo.plc_di_mapping_master WHERE meter_id IS NULL) AS di_mapping_without_meter_id,
        (SELECT COUNT(*) FROM dbo.device_events WHERE meter_id IS NOT NULL) AS device_events_with_meter_id,
        (SELECT COUNT(*) FROM dbo.device_events WHERE meter_id IS NULL) AS device_events_without_meter_id;
');
