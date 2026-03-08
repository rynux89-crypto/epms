-- EPMS KPI extraction (sample)
SET NOCOUNT ON;
DECLARE @t DATETIME=(SELECT MAX(measured_at) FROM dbo.measurements);
DECLARE @w DATETIME=DATEADD(hour,-24,@t);

WITH base AS (
  SELECT *
  FROM dbo.measurements
  WHERE measured_at>@w AND measured_at<=@t
),
lm AS (
  SELECT meter_id, MAX(measured_at) AS last_ts
  FROM dbo.measurements
  GROUP BY meter_id
),
alarm30 AS (
  SELECT COUNT(*) AS c
  FROM dbo.alarm_log
  WHERE triggered_at>DATEADD(day,-30,@t) AND triggered_at<=@t
),
topb AS (
  SELECT TOP 1
      ISNULL(NULLIF(LTRIM(RTRIM(building_name)),''),'(미분류)') AS b,
      AVG(active_power_total) AS kw
  FROM dbo.vw_meter_measurements
  WHERE measured_at>@w AND measured_at<=@t
  GROUP BY ISNULL(NULLIF(LTRIM(RTRIM(building_name)),''),'(미분류)')
  ORDER BY AVG(active_power_total) DESC
)
SELECT
  CONVERT(varchar(19),@t,120) AS anchor_time,
  CAST((SELECT COUNT(*) FROM dbo.meters) AS int) AS meters_total,
  CAST((SELECT COUNT(DISTINCT meter_id)
        FROM dbo.measurements
        WHERE measured_at>DATEADD(minute,-15,@t) AND measured_at<=@t) AS int) AS meters_reporting_15m,
  CAST((SELECT SUM(CASE WHEN last_ts>DATEADD(hour,-1,@t) THEN 1 ELSE 0 END) FROM lm) AS int) AS meters_reporting_1h,
  CAST((SELECT COUNT(*) FROM base) AS int) AS samples_24h,
  CAST((SELECT AVG(CASE WHEN power_factor IS NOT NULL THEN power_factor ELSE power_factor_avg END) FROM base) AS decimal(10,4)) AS avg_pf_24h,
  CAST((SELECT 100.0*SUM(CASE WHEN (CASE WHEN power_factor IS NOT NULL THEN power_factor ELSE power_factor_avg END)<0.9 THEN 1 ELSE 0 END)
              /NULLIF(COUNT(CASE WHEN (CASE WHEN power_factor IS NOT NULL THEN power_factor ELSE power_factor_avg END) IS NOT NULL THEN 1 END),0)
        FROM base) AS decimal(10,2)) AS pf_lt_09_pct,
  CAST((SELECT 100.0*SUM(CASE WHEN frequency BETWEEN 59.8 AND 60.2 THEN 1 ELSE 0 END)/NULLIF(COUNT(frequency),0) FROM base) AS decimal(10,2)) AS freq_in_range_pct,
  CAST((SELECT 100.0*SUM(CASE WHEN voltage_unbalance_rate>2.0 THEN 1 ELSE 0 END)/NULLIF(COUNT(voltage_unbalance_rate),0) FROM base) AS decimal(10,2)) AS unbalance_gt2_pct,
  CAST((SELECT 100.0*SUM(CASE WHEN harmonic_distortion_rate>5.0 THEN 1 ELSE 0 END)/NULLIF(COUNT(harmonic_distortion_rate),0) FROM base) AS decimal(10,2)) AS thd_gt5_pct,
  CAST((SELECT c FROM alarm30) AS int) AS alarms_30d,
  CONVERT(varchar(19),(SELECT MAX(triggered_at) FROM dbo.alarm_log),120) AS alarm_last_time,
  (SELECT b FROM topb) AS top_building_kw,
  CAST((SELECT kw FROM topb) AS decimal(18,2)) AS top_building_avg_kw;
