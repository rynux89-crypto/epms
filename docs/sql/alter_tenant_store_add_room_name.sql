USE [epms];
GO

IF COL_LENGTH('dbo.tenant_store', 'room_name') IS NULL
BEGIN
    ALTER TABLE dbo.tenant_store
        ADD room_name varchar(50) NULL;
END
GO
