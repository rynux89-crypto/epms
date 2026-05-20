IF OBJECT_ID('dbo.epms_carbon_factor', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.epms_carbon_factor (
        factor_code varchar(50) NOT NULL PRIMARY KEY,
        factor_name nvarchar(240) NULL,
        factor_value decimal(12,6) NOT NULL,
        factor_unit varchar(32) NOT NULL CONSTRAINT DF_epms_carbon_factor_unit DEFAULT ('kgCO2_per_kWh'),
        factor_source nvarchar(400) NULL,
        factor_note nvarchar(1000) NULL,
        is_active bit NOT NULL CONSTRAINT DF_epms_carbon_factor_is_active DEFAULT (1),
        is_default bit NOT NULL CONSTRAINT DF_epms_carbon_factor_is_default DEFAULT (0),
        created_at datetime2 NOT NULL CONSTRAINT DF_epms_carbon_factor_created_at DEFAULT (sysdatetime()),
        updated_at datetime2 NOT NULL CONSTRAINT DF_epms_carbon_factor_updated_at DEFAULT (sysdatetime())
    );
END
GO

IF COL_LENGTH('dbo.epms_carbon_factor', 'factor_name') IS NULL
    ALTER TABLE dbo.epms_carbon_factor ADD factor_name nvarchar(240) NULL;
GO

ALTER TABLE dbo.epms_carbon_factor ALTER COLUMN factor_name nvarchar(240) NULL;
GO

ALTER TABLE dbo.epms_carbon_factor ALTER COLUMN factor_source nvarchar(400) NULL;
GO

ALTER TABLE dbo.epms_carbon_factor ALTER COLUMN factor_note nvarchar(1000) NULL;
GO

IF COL_LENGTH('dbo.epms_carbon_factor', 'is_active') IS NULL
    ALTER TABLE dbo.epms_carbon_factor ADD is_active bit NOT NULL CONSTRAINT DF_epms_carbon_factor_is_active DEFAULT (1);
GO

IF COL_LENGTH('dbo.epms_carbon_factor', 'is_default') IS NULL
    ALTER TABLE dbo.epms_carbon_factor ADD is_default bit NOT NULL CONSTRAINT DF_epms_carbon_factor_is_default DEFAULT (0);
GO

IF COL_LENGTH('dbo.epms_carbon_factor', 'created_at') IS NULL
    ALTER TABLE dbo.epms_carbon_factor ADD created_at datetime2 NOT NULL CONSTRAINT DF_epms_carbon_factor_created_at DEFAULT (sysdatetime());
GO

IF OBJECT_ID('dbo.epms_building_carbon_daily', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.epms_building_carbon_daily (
        scope_code varchar(120) NOT NULL,
        building_name nvarchar(400) NULL,
        emission_date date NOT NULL,
        factor_code varchar(50) NULL,
        usage_kwh decimal(18,6) NOT NULL,
        emission_factor decimal(12,6) NOT NULL,
        co2_kg decimal(18,6) NOT NULL,
        factor_source nvarchar(400) NULL,
        factor_note nvarchar(1000) NULL,
        calculated_at datetime2 NOT NULL CONSTRAINT DF_epms_building_carbon_daily_calculated_at DEFAULT (sysdatetime()),
        CONSTRAINT PK_epms_building_carbon_daily PRIMARY KEY (scope_code, emission_date)
    );
END
GO

ALTER TABLE dbo.epms_building_carbon_daily ALTER COLUMN building_name nvarchar(400) NULL;
GO

IF COL_LENGTH('dbo.epms_building_carbon_daily', 'factor_code') IS NULL
    ALTER TABLE dbo.epms_building_carbon_daily ADD factor_code varchar(50) NULL;
GO

ALTER TABLE dbo.epms_building_carbon_daily ALTER COLUMN factor_source nvarchar(400) NULL;
GO

ALTER TABLE dbo.epms_building_carbon_daily ALTER COLUMN factor_note nvarchar(1000) NULL;
GO

IF OBJECT_ID('dbo.epms_carbon_factor_history', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.epms_carbon_factor_history (
        history_id bigint IDENTITY(1,1) NOT NULL PRIMARY KEY,
        factor_code varchar(50) NOT NULL,
        factor_name nvarchar(240) NULL,
        factor_value decimal(12,6) NOT NULL,
        factor_unit varchar(32) NOT NULL,
        factor_source nvarchar(400) NULL,
        factor_note nvarchar(1000) NULL,
        change_action varchar(20) NOT NULL,
        changed_at datetime2 NOT NULL CONSTRAINT DF_epms_carbon_factor_history_changed_at DEFAULT (sysdatetime())
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM dbo.epms_carbon_factor WHERE factor_code = 'DEFAULT_ELECTRICITY')
BEGIN
    INSERT INTO dbo.epms_carbon_factor (
        factor_code,
        factor_name,
        factor_value,
        factor_unit,
        factor_source,
        factor_note,
        is_active,
        is_default
    )
    VALUES (
        'DEFAULT_ELECTRICITY',
        N'Default electricity factor',
        0.450000,
        'kgCO2_per_kWh',
        N'SYSTEM_DEFAULT',
        N'Initial default factor. Update this value to match your reporting standard.',
        1,
        1
    );
END
GO
