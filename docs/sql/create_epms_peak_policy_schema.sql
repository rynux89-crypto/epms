IF OBJECT_ID('dbo.peak_policy', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.peak_policy (
        policy_id BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        store_id INT NOT NULL,
        peak_limit_kw FLOAT NOT NULL,
        warning_threshold_pct FLOAT NOT NULL,
        control_threshold_pct FLOAT NOT NULL,
        priority_level INT NOT NULL CONSTRAINT DF_peak_policy_priority_level DEFAULT (5),
        control_enabled BIT NOT NULL CONSTRAINT DF_peak_policy_control_enabled DEFAULT (0),
        effective_from DATE NOT NULL,
        effective_to DATE NULL,
        notes NVARCHAR(1000) NULL,
        created_at DATETIME2 NOT NULL CONSTRAINT DF_peak_policy_created_at DEFAULT (SYSDATETIME()),
        updated_at DATETIME2 NOT NULL CONSTRAINT DF_peak_policy_updated_at DEFAULT (SYSDATETIME()),
        CONSTRAINT FK_peak_policy_store FOREIGN KEY (store_id) REFERENCES dbo.tenant_store(store_id),
        CONSTRAINT CK_peak_policy_peak_limit_kw CHECK (peak_limit_kw > 0),
        CONSTRAINT CK_peak_policy_warning_pct CHECK (warning_threshold_pct > 0 AND warning_threshold_pct <= 100),
        CONSTRAINT CK_peak_policy_control_pct CHECK (control_threshold_pct > 0 AND control_threshold_pct <= 100),
        CONSTRAINT CK_peak_policy_priority_level CHECK (priority_level BETWEEN 1 AND 9),
        CONSTRAINT CK_peak_policy_date_range CHECK (effective_to IS NULL OR effective_to >= effective_from),
        CONSTRAINT CK_peak_policy_threshold_order CHECK (warning_threshold_pct <= control_threshold_pct)
    );
END;

IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IX_peak_policy_store_effective'
      AND object_id = OBJECT_ID('dbo.peak_policy')
)
BEGIN
    CREATE INDEX IX_peak_policy_store_effective
        ON dbo.peak_policy (store_id, effective_from DESC, effective_to);
END;
