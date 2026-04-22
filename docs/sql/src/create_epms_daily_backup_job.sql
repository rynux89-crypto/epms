/*
  Create SQL Server Agent job for EPMS daily full backup.
  Default schedule: every day at 02:00.
  The job runs the local PowerShell script:
    C:\Tomcat 9.0\webapps\ROOT\scripts\backup_epms_daily.ps1

  Edit the variables in the next block before running on a new server.
*/

USE [msdb];
GO

DECLARE @jobName sysname = N'EPMS Daily Full Backup';
DECLARE @scriptPath nvarchar(4000) = N'C:\Tomcat 9.0\webapps\ROOT\scripts\backup_epms_daily.ps1';
DECLARE @dbServer nvarchar(4000) = N'localhost,1433';
DECLARE @dbName nvarchar(4000) = N'EPMS';
DECLARE @dbUser nvarchar(4000) = N'sa';
DECLARE @dbPassword nvarchar(4000) = N'1234';
DECLARE @backupDir nvarchar(4000) = N'C:\backup';
DECLARE @retainDays int = 7;
DECLARE @startTime int = 020000;
DECLARE @scheduleName sysname = N'EPMS Daily 0200';
DECLARE @command nvarchar(max) =
    N'powershell -NoProfile -ExecutionPolicy Bypass -File "' + @scriptPath +
    N'" -Server "' + @dbServer +
    N'" -Database "' + @dbName +
    N'" -User "' + @dbUser +
    N'" -Password "' + @dbPassword +
    N'" -BackupDir "' + @backupDir +
    N'" -RetainDays ' + CAST(@retainDays AS nvarchar(20));

IF EXISTS (SELECT 1 FROM dbo.sysjobs WHERE name = @jobName)
BEGIN
    EXEC dbo.sp_delete_job @job_name = @jobName, @delete_unused_schedule = 1;
END
GO

EXEC dbo.sp_add_job
    @job_name = N'EPMS Daily Full Backup',
    @enabled = 1,
    @description = N'Compressed daily full backup for EPMS with cleanup of old .bak files.';
GO

EXEC dbo.sp_add_jobstep
    @job_name = N'EPMS Daily Full Backup',
    @step_name = N'Run Backup Script',
    @subsystem = N'CmdExec',
    @command = @command,
    @retry_attempts = 1,
    @retry_interval = 5;
GO

EXEC dbo.sp_add_schedule
    @schedule_name = @scheduleName,
    @enabled = 1,
    @freq_type = 4,
    @freq_interval = 1,
    @active_start_time = @startTime;
GO

EXEC dbo.sp_attach_schedule
    @job_name = N'EPMS Daily Full Backup',
    @schedule_name = @scheduleName;
GO

EXEC dbo.sp_add_jobserver
    @job_name = N'EPMS Daily Full Backup';
GO

SELECT
    @jobName AS job_name,
    @scheduleName AS schedule_name,
    @dbServer AS db_server,
    @dbName AS db_name,
    @backupDir AS backup_dir,
    @retainDays AS retain_days,
    @startTime AS start_time;
GO
