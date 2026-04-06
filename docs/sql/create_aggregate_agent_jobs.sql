/*
   SQL Server Agent jobs for EPMS aggregate measurements

   Purpose
   - Hourly aggregation every 15 minutes
   - Daily rollup at 00:10
   - Monthly rollup on day 1
   - Yearly rollup on Jan 1

   Usage
   1. Open this script in SSMS.
   2. Adjust @TargetDb if your EPMS database name is not EPMS.
   3. Execute against msdb.

   Notes
   - Safe to re-run. Existing jobs with the same names are dropped and recreated.
   - Requires SQL Server Agent and permission to manage Agent jobs.
*/

USE msdb;
GO

DECLARE @TargetDb sysname = N'EPMS';
DECLARE @HourlyJobName sysname = N'EPMS Aggregate Hourly';
DECLARE @RollupJobName sysname = N'EPMS Aggregate Rollup';

DECLARE @HourlyCommand nvarchar(max) =
    N'USE ' + QUOTENAME(@TargetDb) + N';' + CHAR(13) + CHAR(10) +
    N'EXEC dbo.sp_aggregate_hourly_measurements;';

DECLARE @RollupCommand nvarchar(max) =
    N'USE ' + QUOTENAME(@TargetDb) + N';' + CHAR(13) + CHAR(10) +
    N'EXEC dbo.sp_aggregate_daily_measurements;' + CHAR(13) + CHAR(10) +
    N'IF DAY(GETDATE()) = 1 EXEC dbo.sp_aggregate_monthly_measurements;' + CHAR(13) + CHAR(10) +
    N'IF MONTH(GETDATE()) = 1 AND DAY(GETDATE()) = 1 EXEC dbo.sp_aggregate_yearly_measurements;';

IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = @HourlyJobName)
BEGIN
    EXEC msdb.dbo.sp_delete_job @job_name = @HourlyJobName, @delete_unused_schedule = 1;
END

IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = @RollupJobName)
BEGIN
    EXEC msdb.dbo.sp_delete_job @job_name = @RollupJobName, @delete_unused_schedule = 1;
END

EXEC msdb.dbo.sp_add_job
    @job_name = @HourlyJobName,
    @enabled = 1,
    @description = N'Run EPMS hourly aggregation every 15 minutes.',
    @category_name = N'[Uncategorized (Local)]';

EXEC msdb.dbo.sp_add_jobstep
    @job_name = @HourlyJobName,
    @step_name = N'Aggregate Hourly Measurements',
    @subsystem = N'TSQL',
    @database_name = N'master',
    @command = @HourlyCommand,
    @on_success_action = 1,
    @on_fail_action = 2;

EXEC msdb.dbo.sp_add_jobschedule
    @job_name = @HourlyJobName,
    @name = N'Every 15 Minutes',
    @enabled = 1,
    @freq_type = 4,
    @freq_interval = 1,
    @freq_subday_type = 4,
    @freq_subday_interval = 15,
    @active_start_date = 20260403,
    @active_start_time = 000000;

EXEC msdb.dbo.sp_add_jobserver
    @job_name = @HourlyJobName,
    @server_name = N'(local)';

EXEC msdb.dbo.sp_add_job
    @job_name = @RollupJobName,
    @enabled = 1,
    @description = N'Run EPMS daily rollup aggregation and execute monthly/yearly rollups when applicable.',
    @category_name = N'[Uncategorized (Local)]';

EXEC msdb.dbo.sp_add_jobstep
    @job_name = @RollupJobName,
    @step_name = N'Aggregate Daily Monthly Yearly Measurements',
    @subsystem = N'TSQL',
    @database_name = N'master',
    @command = @RollupCommand,
    @on_success_action = 1,
    @on_fail_action = 2;

EXEC msdb.dbo.sp_add_jobschedule
    @job_name = @RollupJobName,
    @name = N'Daily 00:10',
    @enabled = 1,
    @freq_type = 4,
    @freq_interval = 1,
    @active_start_date = 20260404,
    @active_start_time = 001000;

EXEC msdb.dbo.sp_add_jobserver
    @job_name = @RollupJobName,
    @server_name = N'(local)';

SELECT
    name,
    enabled,
    description
FROM msdb.dbo.sysjobs
WHERE name IN (@HourlyJobName, @RollupJobName)
ORDER BY name;
GO
