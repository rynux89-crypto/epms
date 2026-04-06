SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;

IF OBJECT_ID('dbo.plc_ai_mapping_master', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.plc_ai_mapping_master (
        plc_id INT NOT NULL,
        meter_id INT NOT NULL,
        float_index INT NOT NULL,
        token NVARCHAR(100) NOT NULL,
        reg_address INT NOT NULL,
        byte_order NVARCHAR(10) NOT NULL CONSTRAINT DF_plc_ai_mapping_master_byte_order DEFAULT ('ABCD'),
        measurement_column NVARCHAR(128) NULL,
        target_table NVARCHAR(64) NOT NULL CONSTRAINT DF_plc_ai_mapping_master_target_table DEFAULT ('measurements'),
        db_insert_yn BIT NOT NULL CONSTRAINT DF_plc_ai_mapping_master_db_insert DEFAULT ((1)),
        enabled BIT NOT NULL CONSTRAINT DF_plc_ai_mapping_master_enabled DEFAULT ((1)),
        note NVARCHAR(400) NULL,
        updated_at DATETIME2(7) NOT NULL CONSTRAINT DF_plc_ai_mapping_master_updated DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT PK_plc_ai_mapping_master PRIMARY KEY (plc_id, meter_id, float_index)
    );
END;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.plc_ai_mapping_master') AND name = 'IX_plc_ai_mapping_master_token_idx')
    CREATE INDEX IX_plc_ai_mapping_master_token_idx ON dbo.plc_ai_mapping_master (token, float_index);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.plc_ai_mapping_master') AND name = 'IX_plc_ai_mapping_master_meter_addr')
    CREATE INDEX IX_plc_ai_mapping_master_meter_addr ON dbo.plc_ai_mapping_master (plc_id, meter_id, reg_address);
GO

IF OBJECT_ID('dbo.plc_di_mapping_master', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.plc_di_mapping_master (
        plc_id INT NOT NULL,
        point_id INT NOT NULL,
        di_address INT NOT NULL,
        bit_no INT NOT NULL,
        tag_name NVARCHAR(255) NULL,
        item_name NVARCHAR(255) NULL,
        panel_name NVARCHAR(255) NULL,
        enabled BIT NOT NULL CONSTRAINT DF_plc_di_mapping_master_enabled DEFAULT ((1)),
        note NVARCHAR(400) NULL,
        updated_at DATETIME2(7) NOT NULL CONSTRAINT DF_plc_di_mapping_master_updated DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT PK_plc_di_mapping_master PRIMARY KEY (plc_id, point_id, di_address, bit_no)
    );
END;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.plc_di_mapping_master') AND name = 'IX_plc_di_mapping_master_addr')
    CREATE INDEX IX_plc_di_mapping_master_addr ON dbo.plc_di_mapping_master (plc_id, di_address, bit_no);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.plc_di_mapping_master') AND name = 'IX_plc_di_mapping_master_panel')
    CREATE INDEX IX_plc_di_mapping_master_panel ON dbo.plc_di_mapping_master (panel_name, item_name);
GO

;WITH ai_src AS (
    SELECT
        pm.plc_id,
        pm.meter_id,
        ROW_NUMBER() OVER (PARTITION BY pm.plc_id, pm.meter_id ORDER BY (SELECT 1)) AS float_index,
        UPPER(LTRIM(RTRIM(CASE WHEN x.i.value('.', 'nvarchar(100)') = 'KHH' THEN 'KWH' ELSE x.i.value('.', 'nvarchar(100)') END))) AS token,
        pm.start_address + ((ROW_NUMBER() OVER (PARTITION BY pm.plc_id, pm.meter_id ORDER BY (SELECT 1)) - 1) * 2) AS reg_address,
        COALESCE(NULLIF(pm.byte_order, ''), 'ABCD') AS byte_order
    FROM dbo.plc_meter_map pm
    CROSS APPLY (
        SELECT TRY_CAST('<r><i>' +
                        REPLACE(REPLACE(REPLACE(ISNULL(pm.metric_order, ''), '&', '&amp;'), '<', '&lt;'), ',', '</i><i>') +
                        '</i></r>' AS XML) AS metric_xml
    ) q
    CROSS APPLY q.metric_xml.nodes('/r/i') x(i)
    WHERE pm.enabled = 1
      AND ISNULL(pm.metric_order, '') <> ''
),
ai_meta AS (
    SELECT
        UPPER(LTRIM(RTRIM(token))) AS token,
        float_index,
        measurement_column,
        target_table,
        is_supported,
        note
    FROM dbo.plc_ai_measurements_match
),
ai_seed AS (
    SELECT
        s.plc_id,
        s.meter_id,
        s.float_index,
        s.token,
        s.reg_address,
        s.byte_order,
        CASE
            WHEN s.token = 'IR' THEN NULL
            WHEN s.token = 'VA' AND s.float_index = 8 THEN 'phase_voltage_avg'
            WHEN s.token = 'VA' AND s.float_index = 18 THEN 'apparent_power_total'
            WHEN s.token = 'VAH' AND s.float_index = 19 THEN 'apparent_energy_total'
            WHEN s.token = 'KWH' AND s.float_index = 17 THEN 'energy_consumed_total'
            WHEN s.token = 'PST' AND s.float_index = 63 THEN 'flicker_pst'
            WHEN s.token = 'PLT' AND s.float_index = 64 THEN 'flicker_plt'
            ELSE m.measurement_column
        END AS measurement_column,
        CASE
            WHEN s.token IN ('PST', 'PLT') THEN 'flicker_measurements'
            WHEN s.token = 'IR' THEN 'measurements'
            ELSE COALESCE(NULLIF(m.target_table, ''), 'measurements')
        END AS target_table,
        CASE
            WHEN s.token = 'IR' THEN CAST(0 AS BIT)
            WHEN m.is_supported IS NULL THEN CAST(0 AS BIT)
            ELSE CAST(m.is_supported AS BIT)
        END AS db_insert_yn,
        CAST(1 AS BIT) AS enabled,
        CASE
            WHEN s.token = 'IR' THEN N'DB 미적재 PLC 전용'
            WHEN s.token = 'VA' AND s.float_index = 8 THEN N'상전압평균'
            WHEN s.token = 'VA' AND s.float_index = 18 THEN N'피상전력'
            WHEN s.token = 'VAH' AND s.float_index = 19 THEN N'피상전력량'
            ELSE m.note
        END AS note
    FROM ai_src s
    LEFT JOIN ai_meta m
      ON m.token = s.token
     AND (m.float_index = s.float_index OR m.float_index IS NULL)
)
MERGE dbo.plc_ai_mapping_master AS t
USING ai_seed AS s
ON (t.plc_id = s.plc_id AND t.meter_id = s.meter_id AND t.float_index = s.float_index)
WHEN MATCHED THEN
    UPDATE SET
        token = s.token,
        reg_address = s.reg_address,
        byte_order = s.byte_order,
        measurement_column = s.measurement_column,
        target_table = s.target_table,
        db_insert_yn = s.db_insert_yn,
        enabled = s.enabled,
        note = s.note,
        updated_at = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (plc_id, meter_id, float_index, token, reg_address, byte_order, measurement_column, target_table, db_insert_yn, enabled, note, updated_at)
    VALUES (s.plc_id, s.meter_id, s.float_index, s.token, s.reg_address, s.byte_order, s.measurement_column, s.target_table, s.db_insert_yn, s.enabled, s.note, SYSUTCDATETIME());
GO

;WITH di_seed AS (
    SELECT
        dt.plc_id,
        dt.point_id,
        dt.di_address,
        dt.bit_no,
        dt.tag_name,
        dt.item_name,
        dt.panel_name,
        CAST(CASE WHEN ISNULL(dm.enabled, 1) = 1 AND ISNULL(dt.enabled, 1) = 1 THEN 1 ELSE 0 END AS BIT) AS enabled,
        CAST(NULL AS NVARCHAR(400)) AS note
    FROM dbo.plc_di_tag_map dt
    LEFT JOIN dbo.plc_di_map dm
      ON dm.plc_id = dt.plc_id
     AND dm.point_id = dt.point_id
)
MERGE dbo.plc_di_mapping_master AS t
USING di_seed AS s
ON (t.plc_id = s.plc_id AND t.point_id = s.point_id AND t.di_address = s.di_address AND t.bit_no = s.bit_no)
WHEN MATCHED THEN
    UPDATE SET
        tag_name = s.tag_name,
        item_name = s.item_name,
        panel_name = s.panel_name,
        enabled = s.enabled,
        note = s.note,
        updated_at = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (plc_id, point_id, di_address, bit_no, tag_name, item_name, panel_name, enabled, note, updated_at)
    VALUES (s.plc_id, s.point_id, s.di_address, s.bit_no, s.tag_name, s.item_name, s.panel_name, s.enabled, s.note, SYSUTCDATETIME());
