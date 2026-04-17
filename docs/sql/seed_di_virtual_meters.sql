SET NOCOUNT ON;
SET XACT_ABORT ON;

BEGIN TRY
    BEGIN TRANSACTION;

    DECLARE @base_meter_id INT = ISNULL((SELECT MAX(meter_id) FROM dbo.meters), 0);

    SET IDENTITY_INSERT dbo.meters ON;

    ;WITH unresolved_groups AS (
        SELECT DISTINCT
            LTRIM(RTRIM(d.item_name)) AS item_name,
            LTRIM(RTRIM(d.panel_name)) AS panel_name
        FROM dbo.plc_di_mapping_master d
        WHERE d.meter_id IS NULL
          AND ISNULL(LTRIM(RTRIM(d.item_name)), '') <> ''
          AND ISNULL(LTRIM(RTRIM(d.panel_name)), '') <> ''
    ),
    missing_groups AS (
        SELECT g.item_name, g.panel_name
        FROM unresolved_groups g
        WHERE NOT EXISTS (
            SELECT 1
            FROM dbo.meters m
            WHERE UPPER(LTRIM(RTRIM(m.name))) = UPPER(g.item_name)
              AND UPPER(LTRIM(RTRIM(m.panel_name))) = UPPER(g.panel_name)
        )
    ),
    seed_rows AS (
        SELECT
            ROW_NUMBER() OVER (ORDER BY g.panel_name, g.item_name) AS rn,
            g.item_name,
            g.panel_name,
            COALESCE(panel_meta.building_name, default_meta.building_name) AS building_name,
            CAST('DI' AS VARCHAR(50)) AS usage_type,
            panel_meta.rated_voltage,
            panel_meta.rated_current
        FROM missing_groups g
        OUTER APPLY (
            SELECT TOP 1
                m.building_name,
                m.rated_voltage,
                m.rated_current
            FROM dbo.meters m
            WHERE UPPER(LTRIM(RTRIM(m.panel_name))) = UPPER(g.panel_name)
            ORDER BY
                CASE WHEN m.rated_voltage IS NULL THEN 1 ELSE 0 END,
                CASE WHEN m.rated_current IS NULL THEN 1 ELSE 0 END,
                m.meter_id
        ) panel_meta
        OUTER APPLY (
            SELECT TOP 1
                m.building_name
            FROM dbo.meters m
            WHERE ISNULL(LTRIM(RTRIM(m.building_name)), '') <> ''
            GROUP BY m.building_name
            ORDER BY COUNT(*) DESC, m.building_name
        ) default_meta
    )
    INSERT INTO dbo.meters (
        meter_id,
        name,
        panel_name,
        building_name,
        usage_type,
        rated_voltage,
        rated_current
    )
    SELECT
        @base_meter_id + s.rn,
        s.item_name,
        s.panel_name,
        s.building_name,
        s.usage_type,
        s.rated_voltage,
        s.rated_current
    FROM seed_rows s;

    UPDATE d
    SET d.meter_id = m.meter_id
    FROM dbo.plc_di_mapping_master d
    JOIN dbo.meters m
      ON UPPER(LTRIM(RTRIM(m.name))) = UPPER(LTRIM(RTRIM(d.item_name)))
     AND UPPER(LTRIM(RTRIM(m.panel_name))) = UPPER(LTRIM(RTRIM(d.panel_name)))
    WHERE d.meter_id IS NULL;

    SET IDENTITY_INSERT dbo.meters OFF;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF (OBJECT_ID('dbo.meters', 'U') IS NOT NULL)
    BEGIN
        BEGIN TRY
            SET IDENTITY_INSERT dbo.meters OFF;
        END TRY
        BEGIN CATCH
        END CATCH;
    END

    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;
    THROW;
END CATCH;

SELECT COUNT(*) AS di_virtual_meter_count
FROM dbo.meters
WHERE usage_type = 'DI';

SELECT COUNT(*) AS di_mapping_without_meter_id
FROM dbo.plc_di_mapping_master
WHERE meter_id IS NULL;

SELECT meter_id, name, panel_name, building_name, usage_type
FROM dbo.meters
WHERE usage_type = 'DI'
ORDER BY meter_id;
