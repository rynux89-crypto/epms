IF OBJECT_ID('dbo.epms_carbon_factor', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.epms_carbon_factor (
        factor_code varchar(50) NOT NULL PRIMARY KEY,
        factor_value decimal(12,6) NOT NULL,
        factor_unit varchar(32) NOT NULL CONSTRAINT DF_epms_carbon_factor_unit DEFAULT ('kgCO2_per_kWh'),
        factor_source nvarchar(200) NULL,
        factor_note nvarchar(500) NULL,
        updated_at datetime2 NOT NULL CONSTRAINT DF_epms_carbon_factor_updated_at DEFAULT (sysdatetime())
    );
END
GO

IF OBJECT_ID('dbo.epms_building_carbon_daily', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.epms_building_carbon_daily (
        scope_code varchar(120) NOT NULL,
        building_name nvarchar(200) NULL,
        emission_date date NOT NULL,
        usage_kwh decimal(18,6) NOT NULL,
        emission_factor decimal(12,6) NOT NULL,
        co2_kg decimal(18,6) NOT NULL,
        factor_source nvarchar(200) NULL,
        factor_note nvarchar(500) NULL,
        calculated_at datetime2 NOT NULL CONSTRAINT DF_epms_building_carbon_daily_calculated_at DEFAULT (sysdatetime()),
        CONSTRAINT PK_epms_building_carbon_daily PRIMARY KEY (scope_code, emission_date)
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM dbo.epms_carbon_factor WHERE factor_code = 'DEFAULT_ELECTRICITY')
BEGIN
    INSERT INTO dbo.epms_carbon_factor (
        factor_code,
        factor_value,
        factor_unit,
        factor_source,
        factor_note
    )
    VALUES (
        'DEFAULT_ELECTRICITY',
        0.450000,
        'kgCO2_per_kWh',
        N'SYSTEM_DEFAULT',
        N'Initial default factor. Update this value to match your reporting standard.'
    );
END
GO
