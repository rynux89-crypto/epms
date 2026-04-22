/*
   SQL Server Agent job for EPMS peak 15-minute demand summary

   Purpose
   - Refresh dbo.peak_15min_summary on a short interval
   - Keep Peak management dashboard on pre-aggregated data

   Usage
   1. Open this script in SSMS.
   2. Adjust @TargetDb if your EPMS database name is not EPMS.
   3. Execute against msdb.

   Notes
   - Safe to re-run. Existing job with the same name is dropped and recreated.
   - Requires dbo.sp_refresh_peak_15min_summary to exist in the target database.
   - Recommended schedule: every 15 minutes.
*/

USE msdb;
GO

DECLARE @TargetDb sysname = N'EPMS';
DECLARE @JobName sysname = N'EPMS Peak 15Min Summary Refresh';

DECLARE @Command nvarchar(max) =
    N'USE ' + QUOTENAME(@TargetDb) + N';' + CHAR(13) + CHAR(10) +
    N'EXEC dbo.sp_refresh_peak_15min_summary @days_back = 35;';

IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = @JobName)
BEGIN
    EXEC msdb.dbo.sp_delete_job @job_name = @JobName, @delete_unused_schedule = 1;
END

EXEC msdb.dbo.sp_add_job
    @job_name = @JobName,
    @enabled = 1,
    @description = N'Refresh EPMS 15-minute peak demand summary every 15 minutes.',
    @category_name = N'[Uncategorized (Local)]';

EXEC msdb.dbo.sp_add_jobstep
    @job_name = @JobName,
    @step_name = N'Refresh Peak 15Min Summary',
    @subsystem = N'TSQL',
    @database_name = N'master',
    @command = @Command,
    @on_success_action = 1,
    @on_fail_action = 2;

EXEC msdb.dbo.sp_add_jobschedule
    @job_name = @JobName,
    @name = N'Every 15 Minutes',
    @enabled = 1,
    @freq_type = 4,
    @freq_interval = 1,
    @freq_subday_type = 4,
    @freq_subday_interval = 15,
    @active_start_date = 20260417,
    @active_start_time = 000000;

EXEC msdb.dbo.sp_add_jobserver
    @job_name = @JobName,
    @server_name = N'(local)';

SELECT
    name,
    enabled,
    description
FROM msdb.dbo.sysjobs
WHERE name = @JobName;
GO
