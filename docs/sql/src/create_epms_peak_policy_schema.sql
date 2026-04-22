IF OBJECT_ID('dbo.peak_policy_master', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.peak_policy_master (
        policy_id BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        policy_name NVARCHAR(200) NOT NULL,
        peak_limit_kw FLOAT NOT NULL,
        warning_threshold_pct FLOAT NOT NULL,
        control_threshold_pct FLOAT NOT NULL,
        priority_level INT NOT NULL CONSTRAINT DF_peak_policy_master_priority_level DEFAULT (5),
        control_enabled BIT NOT NULL CONSTRAINT DF_peak_policy_master_control_enabled DEFAULT (0),
        effective_from DATE NOT NULL,
        effective_to DATE NULL,
        notes NVARCHAR(1000) NULL,
        created_at DATETIME2 NOT NULL CONSTRAINT DF_peak_policy_master_created_at DEFAULT (SYSDATETIME()),
        updated_at DATETIME2 NOT NULL CONSTRAINT DF_peak_policy_master_updated_at DEFAULT (SYSDATETIME()),
        CONSTRAINT CK_peak_policy_master_peak_limit_kw CHECK (peak_limit_kw > 0),
        CONSTRAINT CK_peak_policy_master_warning_pct CHECK (warning_threshold_pct > 0 AND warning_threshold_pct <= 100),
        CONSTRAINT CK_peak_policy_master_control_pct CHECK (control_threshold_pct > 0 AND control_threshold_pct <= 100),
        CONSTRAINT CK_peak_policy_master_priority_level CHECK (priority_level BETWEEN 1 AND 9),
        CONSTRAINT CK_peak_policy_master_date_range CHECK (effective_to IS NULL OR effective_to >= effective_from),
        CONSTRAINT CK_peak_policy_master_threshold_order CHECK (warning_threshold_pct <= control_threshold_pct)
    );
END;

IF OBJECT_ID('dbo.peak_policy_store_map', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.peak_policy_store_map (
        map_id BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        policy_id BIGINT NOT NULL,
        store_id INT NOT NULL,
        created_at DATETIME2 NOT NULL CONSTRAINT DF_peak_policy_store_map_created_at DEFAULT (SYSDATETIME()),
        updated_at DATETIME2 NOT NULL CONSTRAINT DF_peak_policy_store_map_updated_at DEFAULT (SYSDATETIME()),
        CONSTRAINT FK_peak_policy_store_map_policy FOREIGN KEY (policy_id) REFERENCES dbo.peak_policy_master(policy_id),
        CONSTRAINT FK_peak_policy_store_map_store FOREIGN KEY (store_id) REFERENCES dbo.tenant_store(store_id),
        CONSTRAINT UQ_peak_policy_store_map UNIQUE (policy_id, store_id)
    );
END;

IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IX_peak_policy_master_effective'
      AND object_id = OBJECT_ID('dbo.peak_policy_master')
)
BEGIN
    CREATE INDEX IX_peak_policy_master_effective
        ON dbo.peak_policy_master (effective_from DESC, effective_to, priority_level);
END;

IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IX_peak_policy_store_map_store'
      AND object_id = OBJECT_ID('dbo.peak_policy_store_map')
)
BEGIN
    CREATE INDEX IX_peak_policy_store_map_store
        ON dbo.peak_policy_store_map (store_id, policy_id);
END;

IF OBJECT_ID('dbo.peak_policy', 'U') IS NOT NULL
AND NOT EXISTS (SELECT 1 FROM dbo.peak_policy_master)
BEGIN
    INSERT INTO dbo.peak_policy_master (
        policy_name, peak_limit_kw, warning_threshold_pct, control_threshold_pct,
        priority_level, control_enabled, effective_from, effective_to, notes, created_at, updated_at
    )
    SELECT
        ts.store_code + N' 기본정책',
        p.peak_limit_kw,
        p.warning_threshold_pct,
        p.control_threshold_pct,
        p.priority_level,
        p.control_enabled,
        p.effective_from,
        p.effective_to,
        p.notes,
        p.created_at,
        p.updated_at
    FROM dbo.peak_policy p
    INNER JOIN dbo.tenant_store ts ON ts.store_id = p.store_id
    ORDER BY p.policy_id;

    ;WITH legacy_rows AS (
        SELECT
            ROW_NUMBER() OVER (ORDER BY p.policy_id) AS rn,
            p.store_id
        FROM dbo.peak_policy p
    ),
    new_rows AS (
        SELECT
            ROW_NUMBER() OVER (ORDER BY pm.policy_id) AS rn,
            pm.policy_id
        FROM dbo.peak_policy_master pm
    )
    INSERT INTO dbo.peak_policy_store_map (policy_id, store_id)
    SELECT nr.policy_id, lr.store_id
    FROM legacy_rows lr
    INNER JOIN new_rows nr ON nr.rn = lr.rn;
END;
