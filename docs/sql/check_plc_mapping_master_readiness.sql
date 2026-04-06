/* ---------------------------------------------------------------------------
   PLC Mapping Master Readiness Check

   Purpose
   - Verify whether master tables are complete enough to remove legacy fallback.
   - Compare PLC-level coverage between legacy tables and master tables.

   Recommended use
   1. Run before removing runtime fallback from ModbusConfigRepository.
   2. Confirm every active PLC has AI/DI rows in master tables.
   3. Review token/index duplicates or missing insert mappings.
--------------------------------------------------------------------------- */

PRINT '1) Active PLC coverage by AI master / legacy';
SELECT
    c.plc_id,
    c.enabled,
    ai_master.ai_row_count,
    ai_legacy.ai_row_count AS legacy_ai_row_count,
    CASE
        WHEN ISNULL(ai_master.ai_row_count, 0) > 0 THEN 'READY'
        ELSE 'MISSING_AI_MASTER'
    END AS ai_master_status
FROM dbo.plc_config c
LEFT JOIN (
    SELECT plc_id, COUNT(*) AS ai_row_count
    FROM dbo.plc_ai_mapping_master
    WHERE enabled = 1
    GROUP BY plc_id
) ai_master
    ON ai_master.plc_id = c.plc_id
LEFT JOIN (
    SELECT plc_id, COUNT(*) AS ai_row_count
    FROM dbo.plc_meter_map
    WHERE enabled = 1
    GROUP BY plc_id
) ai_legacy
    ON ai_legacy.plc_id = c.plc_id
WHERE c.enabled = 1
ORDER BY c.plc_id;

PRINT '2) Active PLC coverage by DI master / legacy';
SELECT
    c.plc_id,
    c.enabled,
    di_master.di_row_count,
    di_legacy.di_row_count AS legacy_di_row_count,
    CASE
        WHEN ISNULL(di_master.di_row_count, 0) > 0 THEN 'READY'
        ELSE 'MISSING_DI_MASTER'
    END AS di_master_status
FROM dbo.plc_config c
LEFT JOIN (
    SELECT plc_id, COUNT(*) AS di_row_count
    FROM dbo.plc_di_mapping_master
    WHERE enabled = 1
    GROUP BY plc_id
) di_master
    ON di_master.plc_id = c.plc_id
LEFT JOIN (
    SELECT plc_id, COUNT(*) AS di_row_count
    FROM dbo.plc_di_tag_map
    WHERE enabled = 1
    GROUP BY plc_id
) di_legacy
    ON di_legacy.plc_id = c.plc_id
WHERE c.enabled = 1
ORDER BY c.plc_id;

PRINT '3) AI master rows missing DB insert definition';
SELECT TOP 100
    plc_id,
    meter_id,
    float_index,
    token,
    reg_address,
    measurement_column,
    target_table,
    db_insert_yn,
    note
FROM dbo.plc_ai_mapping_master
WHERE enabled = 1
  AND db_insert_yn = 1
  AND (measurement_column IS NULL OR LTRIM(RTRIM(measurement_column)) = '')
ORDER BY plc_id, meter_id, float_index;

PRINT '4) AI token + float_index duplicates in master';
SELECT
    token,
    float_index,
    COUNT(*) AS dup_count
FROM dbo.plc_ai_mapping_master
WHERE enabled = 1
GROUP BY token, float_index
HAVING COUNT(*) > 1
ORDER BY dup_count DESC, token, float_index;

PRINT '5) DI address duplicates in master';
SELECT
    plc_id,
    di_address,
    bit_no,
    COUNT(*) AS dup_count
FROM dbo.plc_di_mapping_master
WHERE enabled = 1
GROUP BY plc_id, di_address, bit_no
HAVING COUNT(*) > 1
ORDER BY plc_id, di_address, bit_no;

PRINT '6) Final readiness summary';
SELECT
    CASE
        WHEN EXISTS (
            SELECT 1
            FROM dbo.plc_config c
            LEFT JOIN (
                SELECT plc_id, COUNT(*) AS cnt
                FROM dbo.plc_ai_mapping_master
                WHERE enabled = 1
                GROUP BY plc_id
            ) am ON am.plc_id = c.plc_id
            LEFT JOIN (
                SELECT plc_id, COUNT(*) AS cnt
                FROM dbo.plc_di_mapping_master
                WHERE enabled = 1
                GROUP BY plc_id
            ) dm ON dm.plc_id = c.plc_id
            WHERE c.enabled = 1
              AND (ISNULL(am.cnt, 0) = 0 OR ISNULL(dm.cnt, 0) = 0)
        ) THEN 'NOT_READY'
        ELSE 'READY_FOR_FALLBACK_REVIEW'
    END AS fallback_removal_status;
