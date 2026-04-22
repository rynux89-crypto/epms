SET NOCOUNT ON;

PRINT '=== EPMS Peak Management Readiness Check ===';

DECLARE @now DATETIME2 = SYSDATETIME();

SELECT
    @now AS checked_at,
    DB_NAME() AS database_name;

PRINT '--- 1. Core object existence ---';

SELECT
    'dbo.peak_policy_master' AS object_name,
    CASE WHEN OBJECT_ID('dbo.peak_policy_master', 'U') IS NOT NULL THEN 'OK' ELSE 'MISSING' END AS status
UNION ALL
SELECT
    'dbo.peak_policy_store_map',
    CASE WHEN OBJECT_ID('dbo.peak_policy_store_map', 'U') IS NOT NULL THEN 'OK' ELSE 'MISSING' END
UNION ALL
SELECT
    'dbo.peak_15min_summary',
    CASE WHEN OBJECT_ID('dbo.peak_15min_summary', 'U') IS NOT NULL THEN 'OK' ELSE 'MISSING' END
UNION ALL
SELECT
    'dbo.sp_refresh_peak_15min_summary',
    CASE WHEN OBJECT_ID('dbo.sp_refresh_peak_15min_summary', 'P') IS NOT NULL THEN 'OK' ELSE 'MISSING' END;

PRINT '--- 2. SQL Server Agent job existence ---';

IF DB_ID('msdb') IS NOT NULL
BEGIN
    SELECT
        j.name AS job_name,
        CASE WHEN j.enabled = 1 THEN 'ENABLED' ELSE 'DISABLED' END AS job_status
    FROM msdb.dbo.sysjobs AS j
    WHERE j.name = 'EPMS Peak 15min Summary Refresh';

    IF NOT EXISTS (
        SELECT 1
        FROM msdb.dbo.sysjobs
        WHERE name = 'EPMS Peak 15min Summary Refresh'
    )
    BEGIN
        SELECT
            'EPMS Peak 15min Summary Refresh' AS job_name,
            'MISSING' AS job_status;
    END
END
ELSE
BEGIN
    SELECT
        'msdb' AS dependency_name,
        'UNAVAILABLE' AS status;
END;

PRINT '--- 3. Recent measurements status ---';

SELECT
    MAX(m.measured_at) AS latest_measured_at,
    COUNT_BIG(*) AS measurement_row_count
FROM dbo.measurements AS m;

SELECT TOP 10
    m.meter_id,
    MAX(m.measured_at) AS latest_measured_at,
    COUNT_BIG(*) AS row_count_last_24h
FROM dbo.measurements AS m
WHERE m.measured_at >= DATEADD(HOUR, -24, @now)
GROUP BY m.meter_id
ORDER BY latest_measured_at DESC;

PRINT '--- 4. Peak policy status ---';

IF OBJECT_ID('dbo.peak_policy_master', 'U') IS NOT NULL
AND OBJECT_ID('dbo.peak_policy_store_map', 'U') IS NOT NULL
BEGIN
    SELECT
        COUNT(*) AS policy_count,
        SUM(CASE WHEN p.effective_to IS NULL OR p.effective_to >= CAST(@now AS DATE) THEN 1 ELSE 0 END) AS active_or_open_ended_policy_count
    FROM dbo.peak_policy_master AS p;

    SELECT TOP 20
        p.policy_id,
        p.policy_name,
        p.peak_limit_kw,
        p.warning_threshold_pct,
        p.control_threshold_pct,
        p.priority_level,
        p.control_enabled,
        p.effective_from,
        p.effective_to,
        COUNT(m.store_id) AS assigned_store_count
    FROM dbo.peak_policy_master AS p
    LEFT JOIN dbo.peak_policy_store_map AS m
        ON m.policy_id = p.policy_id
    GROUP BY p.policy_id, p.policy_name, p.peak_limit_kw, p.warning_threshold_pct, p.control_threshold_pct,
             p.priority_level, p.control_enabled, p.effective_from, p.effective_to
    ORDER BY p.priority_level ASC, p.policy_id ASC;
END
ELSE
BEGIN
    SELECT
        'dbo.peak_policy_master / dbo.peak_policy_store_map' AS object_name,
        'SKIPPED' AS status;
END;

PRINT '--- 5. 15-minute summary status ---';

IF OBJECT_ID('dbo.peak_15min_summary', 'U') IS NOT NULL
BEGIN
    SELECT
        COUNT(*) AS summary_row_count,
        MAX(bucket_start) AS latest_bucket_start,
        MAX(refreshed_at) AS latest_refreshed_at,
        DATEDIFF(MINUTE, MAX(refreshed_at), @now) AS refresh_lag_minutes
    FROM dbo.peak_15min_summary;

    SELECT TOP 20
        meter_id,
        bucket_start,
        avg_active_power_total,
        refreshed_at
    FROM dbo.peak_15min_summary
    ORDER BY refreshed_at DESC, bucket_start DESC;
END
ELSE
BEGIN
    SELECT
        'dbo.peak_15min_summary' AS object_name,
        'SKIPPED' AS status;
END;

PRINT '--- 6. Tenant-to-meter mapping health ---';

IF OBJECT_ID('dbo.tenant_meter_map', 'U') IS NOT NULL
AND OBJECT_ID('dbo.tenant_store', 'U') IS NOT NULL
BEGIN
    SELECT
        COUNT(*) AS total_mapping_count,
        SUM(CASE WHEN valid_to IS NULL OR valid_to >= CAST(@now AS DATE) THEN 1 ELSE 0 END) AS active_mapping_count
    FROM dbo.tenant_meter_map;

    SELECT TOP 20
        s.store_id,
        s.store_name,
        COUNT(tm.map_id) AS active_mapping_count
    FROM dbo.tenant_store AS s
    LEFT JOIN dbo.tenant_meter_map AS tm
        ON tm.store_id = s.store_id
       AND tm.valid_from <= CAST(@now AS DATE)
       AND (tm.valid_to IS NULL OR tm.valid_to >= CAST(@now AS DATE))
    GROUP BY s.store_id, s.store_name
    HAVING COUNT(tm.map_id) = 0
    ORDER BY s.store_id;
END
ELSE
BEGIN
    SELECT
        'tenant_store / tenant_meter_map' AS object_name,
        'SKIPPED' AS status;
END;

PRINT '=== End of readiness check ===';
