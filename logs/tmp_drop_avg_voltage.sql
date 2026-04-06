SET NOCOUNT ON;
IF COL_LENGTH('dbo.daily_measurements', 'avg_voltage') IS NOT NULL ALTER TABLE dbo.daily_measurements DROP COLUMN avg_voltage;
IF COL_LENGTH('dbo.hourly_measurements', 'avg_voltage') IS NOT NULL ALTER TABLE dbo.hourly_measurements DROP COLUMN avg_voltage;
IF COL_LENGTH('dbo.monthly_measurements', 'avg_voltage') IS NOT NULL ALTER TABLE dbo.monthly_measurements DROP COLUMN avg_voltage;
IF COL_LENGTH('dbo.yearly_measurements', 'avg_voltage') IS NOT NULL ALTER TABLE dbo.yearly_measurements DROP COLUMN avg_voltage;
