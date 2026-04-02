SET NOCOUNT ON;

PRINT '1) AI mapping orphan check';
SELECT 'plc_meter_map' AS src, COUNT(*) AS orphan_cnt
FROM dbo.plc_meter_map pm
LEFT JOIN dbo.meters m ON m.meter_id = pm.meter_id
WHERE m.meter_id IS NULL
UNION ALL
SELECT 'plc_ai_samples', COUNT(*)
FROM dbo.plc_ai_samples s
LEFT JOIN dbo.meters m ON m.meter_id = s.meter_id
WHERE m.meter_id IS NULL
UNION ALL
SELECT 'measurements', COUNT(*)
FROM dbo.measurements x
LEFT JOIN dbo.meters m ON m.meter_id = x.meter_id
WHERE m.meter_id IS NULL
UNION ALL
SELECT 'harmonic_measurements', COUNT(*)
FROM dbo.harmonic_measurements x
LEFT JOIN dbo.meters m ON m.meter_id = x.meter_id
WHERE m.meter_id IS NULL
UNION ALL
SELECT 'flicker_measurements', COUNT(*)
FROM dbo.flicker_measurements x
LEFT JOIN dbo.meters m ON m.meter_id = x.meter_id
WHERE m.meter_id IS NULL;

PRINT '2) Enabled AI map coverage';
SELECT COUNT(*) AS enabled_ai_maps, COUNT(DISTINCT meter_id) AS distinct_meters
FROM dbo.plc_meter_map
WHERE enabled = 1;

SELECT COUNT(*) AS current_meter_count
FROM dbo.meters;

PRINT '3) DI item_name unresolved against meters.name';
WITH meter_names AS (
    SELECT UPPER(LTRIM(RTRIM(name))) AS meter_name
    FROM dbo.meters
    WHERE name IS NOT NULL AND LTRIM(RTRIM(name)) <> ''
),
di_items AS (
    SELECT DISTINCT
        point_id,
        UPPER(LTRIM(RTRIM(ISNULL(item_name, '')))) AS item_name,
        UPPER(LTRIM(RTRIM(ISNULL(panel_name, '')))) AS panel_name
    FROM dbo.plc_di_tag_map
    WHERE enabled = 1
      AND item_name IS NOT NULL
      AND LTRIM(RTRIM(item_name)) <> ''
)
SELECT d.point_id, d.item_name, d.panel_name
FROM di_items d
LEFT JOIN meter_names m ON m.meter_name = d.item_name
WHERE m.meter_name IS NULL
ORDER BY d.item_name, d.panel_name;

PRINT '4) Duplicate panel names in meters';
SELECT UPPER(LTRIM(RTRIM(panel_name))) AS panel_name, COUNT(*) AS meter_count
FROM dbo.meters
WHERE panel_name IS NOT NULL AND LTRIM(RTRIM(panel_name)) <> ''
GROUP BY UPPER(LTRIM(RTRIM(panel_name)))
HAVING COUNT(*) > 1
ORDER BY panel_name;
