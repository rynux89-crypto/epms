SET NOCOUNT ON;
SET XACT_ABORT ON;

/*
Purpose
 - Merge explicitly chosen duplicate rows in dbo.meters into one keeper meter_id.
 - Move historical references to the keeper.
 - Remove the duplicate meter rows.

Important
 - This script does NOT auto-pick duplicates. You must register the pairs below.
 - Review plc_meter_map rows carefully before applying. If two different live PLC
   addresses exist, that may indicate a bad duplicate import rather than a safe
   merge. In that case, keep only the correct live mapping.

How to use
 1. Fill @merge_pairs with (keep_meter_id, drop_meter_id).
 2. Run once with @apply = 0 to preview.
 3. Review the result sets, especially plc_meter_map rows.
 4. Set @apply = 1 and run again to apply.

Current known duplicate candidates on this system when this script was added:
 - 119 <- 207 : EAST_MDB_5B_13 / MDB_5B / 동관
 - 145 <- 208 : EAST_MDB_6B_12 / MDB_6B / 동관
*/

DECLARE @apply bit = 0;

DECLARE @merge_pairs TABLE (
    keep_meter_id int NOT NULL,
    drop_meter_id int NOT NULL,
    PRIMARY KEY (keep_meter_id, drop_meter_id)
);

/* Example:
INSERT INTO @merge_pairs (keep_meter_id, drop_meter_id)
VALUES
    (119, 207),
    (145, 208);
*/

IF NOT EXISTS (SELECT 1 FROM @merge_pairs)
BEGIN
    RAISERROR('No merge pairs registered in @merge_pairs.', 16, 1);
    RETURN;
END;

IF EXISTS (
    SELECT 1
    FROM @merge_pairs
    WHERE keep_meter_id = drop_meter_id
)
BEGIN
    RAISERROR('keep_meter_id and drop_meter_id cannot be the same.', 16, 1);
    RETURN;
END;

IF EXISTS (
    SELECT 1
    FROM @merge_pairs mp
    LEFT JOIN dbo.meters mk ON mk.meter_id = mp.keep_meter_id
    LEFT JOIN dbo.meters md ON md.meter_id = mp.drop_meter_id
    WHERE mk.meter_id IS NULL OR md.meter_id IS NULL
)
BEGIN
    RAISERROR('One or more keep/drop meter ids do not exist in dbo.meters.', 16, 1);
    RETURN;
END;

PRINT 'Preview: meter rows';
SELECT
    mp.keep_meter_id,
    mp.drop_meter_id,
    mk.name AS keep_name,
    mk.panel_name AS keep_panel_name,
    mk.building_name AS keep_building_name,
    md.name AS drop_name,
    md.panel_name AS drop_panel_name,
    md.building_name AS drop_building_name,
    CASE
        WHEN ISNULL(mk.name, '') = ISNULL(md.name, '')
         AND ISNULL(mk.panel_name, '') = ISNULL(md.panel_name, '')
         AND ISNULL(mk.building_name, '') = ISNULL(md.building_name, '')
         AND ISNULL(mk.usage_type, '') = ISNULL(md.usage_type, '')
         AND ISNULL(mk.rated_voltage, -999999.0) = ISNULL(md.rated_voltage, -999999.0)
         AND ISNULL(mk.rated_current, -999999.0) = ISNULL(md.rated_current, -999999.0)
        THEN 'EXACT_SAME_BUSINESS_FIELDS'
        ELSE 'DIFFERENT_FIELDS_REVIEW_REQUIRED'
    END AS review_status
FROM @merge_pairs mp
JOIN dbo.meters mk ON mk.meter_id = mp.keep_meter_id
JOIN dbo.meters md ON md.meter_id = mp.drop_meter_id
ORDER BY mp.keep_meter_id, mp.drop_meter_id;

PRINT 'Preview: reference counts before merge';
SELECT
    mp.keep_meter_id,
    mp.drop_meter_id,
    (SELECT COUNT(*) FROM dbo.measurements x WHERE x.meter_id = mp.drop_meter_id) AS measurements_refs,
    (SELECT COUNT(*) FROM dbo.harmonic_measurements x WHERE x.meter_id = mp.drop_meter_id) AS harmonic_refs,
    (SELECT COUNT(*) FROM dbo.flicker_measurements x WHERE x.meter_id = mp.drop_meter_id) AS flicker_refs,
    (SELECT COUNT(*) FROM dbo.alarm_log x WHERE x.meter_id = mp.drop_meter_id) AS alarm_refs,
    (SELECT COUNT(*) FROM dbo.device_events x WHERE x.device_id = mp.drop_meter_id) AS device_event_refs,
    (SELECT COUNT(*) FROM dbo.daily_measurements x WHERE x.meter_id = mp.drop_meter_id) AS daily_refs,
    (SELECT COUNT(*) FROM dbo.monthly_measurements x WHERE x.meter_id = mp.drop_meter_id) AS monthly_refs,
    (SELECT COUNT(*) FROM dbo.yearly_measurements x WHERE x.meter_id = mp.drop_meter_id) AS yearly_refs,
    (SELECT COUNT(*) FROM dbo.voltage_events x WHERE x.meter_id = mp.drop_meter_id) AS voltage_event_refs,
    (SELECT COUNT(*) FROM dbo.plc_ai_samples x WHERE x.meter_id = mp.drop_meter_id) AS plc_ai_sample_refs,
    (SELECT COUNT(*) FROM dbo.plc_ai_write_task x WHERE x.meter_id = mp.drop_meter_id) AS plc_ai_write_task_refs,
    (SELECT COUNT(*) FROM dbo.plc_meter_map x WHERE x.meter_id = mp.drop_meter_id) AS plc_meter_map_refs,
    (SELECT COUNT(*) FROM dbo.meter_tree x WHERE x.parent_meter_id = mp.drop_meter_id OR x.child_meter_id = mp.drop_meter_id) AS meter_tree_refs
FROM @merge_pairs mp
ORDER BY mp.keep_meter_id, mp.drop_meter_id;

PRINT 'Preview: plc_meter_map rows that need manual review';
SELECT
    mp.keep_meter_id,
    mp.drop_meter_id,
    p.map_id,
    p.plc_id,
    p.meter_id,
    p.start_address,
    p.float_count,
    p.byte_order,
    p.enabled,
    p.metric_order
FROM @merge_pairs mp
JOIN dbo.plc_meter_map p
  ON p.meter_id IN (mp.keep_meter_id, mp.drop_meter_id)
ORDER BY mp.keep_meter_id, mp.drop_meter_id, p.meter_id, p.plc_id, p.start_address;

IF @apply = 0
BEGIN
    PRINT 'Preview only. Set @apply = 1 after review to perform the merge.';
    RETURN;
END;

BEGIN TRY
    BEGIN TRANSACTION;

    UPDATE tgt
    SET tgt.meter_id = mp.keep_meter_id
    FROM dbo.measurements tgt
    JOIN @merge_pairs mp ON mp.drop_meter_id = tgt.meter_id;

    UPDATE tgt
    SET tgt.meter_id = mp.keep_meter_id
    FROM dbo.harmonic_measurements tgt
    JOIN @merge_pairs mp ON mp.drop_meter_id = tgt.meter_id;

    UPDATE tgt
    SET tgt.meter_id = mp.keep_meter_id
    FROM dbo.flicker_measurements tgt
    JOIN @merge_pairs mp ON mp.drop_meter_id = tgt.meter_id;

    UPDATE tgt
    SET tgt.meter_id = mp.keep_meter_id
    FROM dbo.alarm_log tgt
    JOIN @merge_pairs mp ON mp.drop_meter_id = tgt.meter_id;

    UPDATE tgt
    SET tgt.device_id = mp.keep_meter_id
    FROM dbo.device_events tgt
    JOIN @merge_pairs mp ON mp.drop_meter_id = tgt.device_id;

    UPDATE tgt
    SET tgt.meter_id = mp.keep_meter_id
    FROM dbo.daily_measurements tgt
    JOIN @merge_pairs mp ON mp.drop_meter_id = tgt.meter_id;

    UPDATE tgt
    SET tgt.meter_id = mp.keep_meter_id
    FROM dbo.monthly_measurements tgt
    JOIN @merge_pairs mp ON mp.drop_meter_id = tgt.meter_id;

    UPDATE tgt
    SET tgt.meter_id = mp.keep_meter_id
    FROM dbo.yearly_measurements tgt
    JOIN @merge_pairs mp ON mp.drop_meter_id = tgt.meter_id;

    UPDATE tgt
    SET tgt.meter_id = mp.keep_meter_id
    FROM dbo.voltage_events tgt
    JOIN @merge_pairs mp ON mp.drop_meter_id = tgt.meter_id;

    UPDATE tgt
    SET tgt.meter_id = mp.keep_meter_id
    FROM dbo.plc_ai_samples tgt
    JOIN @merge_pairs mp ON mp.drop_meter_id = tgt.meter_id;

    UPDATE tgt
    SET tgt.meter_id = mp.keep_meter_id
    FROM dbo.plc_ai_write_task tgt
    JOIN @merge_pairs mp ON mp.drop_meter_id = tgt.meter_id;

    /*
    plc_meter_map is intentionally deleted, not reassigned.
    If the duplicate row has a different live PLC address, reassigning it would make
    one meter_id receive data from multiple addresses and corrupt future collection.
    Keep only the correct live map row on the keeper meter_id.
    */
    DELETE tgt
    FROM dbo.plc_meter_map tgt
    JOIN @merge_pairs mp ON mp.drop_meter_id = tgt.meter_id;

    DELETE mt
    FROM dbo.meter_tree mt
    JOIN @merge_pairs mp
      ON mt.parent_meter_id = mp.drop_meter_id
      OR mt.child_meter_id = mp.drop_meter_id;

    DELETE m
    FROM dbo.meters m
    JOIN @merge_pairs mp ON mp.drop_meter_id = m.meter_id;

    COMMIT TRANSACTION;
    PRINT 'Meter merge completed.';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;

    THROW;
END CATCH;

PRINT 'Post-check: remaining rows for selected meter ids';
SELECT m.*
FROM dbo.meters m
WHERE m.meter_id IN (
    SELECT keep_meter_id FROM @merge_pairs
    UNION
    SELECT drop_meter_id FROM @merge_pairs
)
ORDER BY m.meter_id;
