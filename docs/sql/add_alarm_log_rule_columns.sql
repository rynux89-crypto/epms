IF COL_LENGTH('dbo.alarm_log','rule_id') IS NULL
    ALTER TABLE dbo.alarm_log ADD rule_id INT NULL;
GO

IF COL_LENGTH('dbo.alarm_log','rule_code') IS NULL
    ALTER TABLE dbo.alarm_log ADD rule_code VARCHAR(50) NULL;
GO

IF COL_LENGTH('dbo.alarm_log','metric_key') IS NULL
    ALTER TABLE dbo.alarm_log ADD metric_key VARCHAR(100) NULL;
GO

IF COL_LENGTH('dbo.alarm_log','source_token') IS NULL
    ALTER TABLE dbo.alarm_log ADD source_token VARCHAR(120) NULL;
GO
