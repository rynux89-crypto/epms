IF OBJECT_ID('dbo.peak_15min_summary', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.peak_15min_summary (
        summary_id BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        meter_id INT NOT NULL,
        bucket_at DATETIME NOT NULL,
        demand_kw FLOAT NOT NULL,
        sample_count INT NOT NULL CONSTRAINT DF_peak_15min_summary_sample_count DEFAULT (0),
        created_at DATETIME2 NOT NULL CONSTRAINT DF_peak_15min_summary_created_at DEFAULT (SYSDATETIME()),
        updated_at DATETIME2 NOT NULL CONSTRAINT DF_peak_15min_summary_updated_at DEFAULT (SYSDATETIME()),
        CONSTRAINT FK_peak_15min_summary_meter FOREIGN KEY (meter_id) REFERENCES dbo.meters(meter_id),
        CONSTRAINT UQ_peak_15min_summary_meter_bucket UNIQUE (meter_id, bucket_at)
    );
END;
GO

IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IX_peak_15min_summary_bucket'
      AND object_id = OBJECT_ID('dbo.peak_15min_summary')
)
BEGIN
    CREATE INDEX IX_peak_15min_summary_bucket
        ON dbo.peak_15min_summary (bucket_at DESC, meter_id)
        INCLUDE (demand_kw, sample_count);
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_refresh_peak_15min_summary
    @days_back INT = 35
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @from_at DATETIME = DATEADD(day, -ABS(ISNULL(@days_back, 35)), GETDATE());

    ;WITH src AS (
        SELECT
            ms.meter_id,
            DATEADD(minute, (DATEDIFF(minute, 0, ms.measured_at) / 15) * 15, 0) AS bucket_at,
            AVG(CAST(ms.active_power_total AS FLOAT)) AS demand_kw,
            COUNT(*) AS sample_count
        FROM dbo.measurements ms
        WHERE ms.active_power_total IS NOT NULL
          AND ms.measured_at >= @from_at
        GROUP BY
            ms.meter_id,
            DATEADD(minute, (DATEDIFF(minute, 0, ms.measured_at) / 15) * 15, 0)
    )
    MERGE dbo.peak_15min_summary AS t
    USING src
       ON t.meter_id = src.meter_id
      AND t.bucket_at = src.bucket_at
    WHEN MATCHED THEN
        UPDATE SET
            t.demand_kw = src.demand_kw,
            t.sample_count = src.sample_count,
            t.updated_at = SYSDATETIME()
    WHEN NOT MATCHED THEN
        INSERT (meter_id, bucket_at, demand_kw, sample_count, created_at, updated_at)
        VALUES (src.meter_id, src.bucket_at, src.demand_kw, src.sample_count, SYSDATETIME(), SYSDATETIME());

    DELETE
    FROM dbo.peak_15min_summary
    WHERE bucket_at < @from_at;
END;
GO
